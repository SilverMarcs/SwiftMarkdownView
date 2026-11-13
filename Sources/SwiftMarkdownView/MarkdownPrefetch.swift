import SwiftUI

extension View {
    /// Lays out Markdown texts off the main thread before they're shown, so
    /// a `SwiftMarkdownView` showing one of them, such as a row scrolling
    /// into a lazy stack, doesn't typeset it on the main thread.
    ///
    /// Texts are laid out in the style and at the width of the views showing
    /// any of them, once one has appeared. Pass the texts most likely to be
    /// shown next first, and leave out text that's still changing, such as a
    /// reply that's streaming in. A text's images are loaded first, up to a
    /// limit, so it's laid out at their sizes. Prepared text is let go when
    /// this view disappears. It has no effect on iOS.
    public func markdownPrefetch(_ texts: [String]) -> some View {
        #if os(macOS)
        modifier(MarkdownPrefetchModifier(texts: texts))
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MarkdownPrefetchModifier: ViewModifier {
    let texts: [String]
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: texts, initial: true) {
                MarkdownPrefetcher.shared.want(texts, for: id)
            }
            .onDisappear {
                MarkdownPrefetcher.shared.stopWanting(for: id)
            }
    }
}

/// The parts of a render request that change how text lays out, apart from
/// the text.
struct MarkdownRenderStyle: Hashable {
    let fontSize: CGFloat
    let themeName: String
    let codeBlockBackground: Color
}

extension MarkdownRenderRequest {
    var style: MarkdownRenderStyle {
        MarkdownRenderStyle(fontSize: fontSize, themeName: themeName, codeBlockBackground: codeBlockBackground)
    }

    init(text: String, style: MarkdownRenderStyle) {
        self.init(text: text, fontSize: style.fontSize, themeName: style.themeName, codeBlockBackground: style.codeBlockBackground)
    }
}

/// What a prepared text's image blocks were laid out as: the image store's
/// state for each, by block ID, from one loader at one display scale.
struct MarkdownPreparedImages: @unchecked Sendable {
    let loaderID: AnyHashable
    let states: [Int: MarkdownImageStore.LayoutState]
    let displayScale: CGFloat
}

/// A rendered document's text system, laid out at one width, for a text view
/// to adopt.
final class MarkdownPreparedText: @unchecked Sendable {
    let request: MarkdownRenderRequest
    let document: MarkdownRenderedDocument
    let storage: NSTextStorage
    let layoutManager: MarkdownLayoutManager
    let container: NSTextContainer
    let size: CGSize
    let fittedTableIDs: Set<Int>
    /// How its images were laid out, if it has any.
    let images: MarkdownPreparedImages?

    /// Builds the text system and lays it out. It can run on any thread,
    /// since nothing else touches these objects until a view adopts them on
    /// the main thread. A document with images needs `images`, the sizes a
    /// view would lay them out at.
    nonisolated init(
        request: MarkdownRenderRequest,
        document: MarkdownRenderedDocument,
        width: CGFloat,
        images: MarkdownPreparedImages? = nil
    ) {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let container = NSTextContainer()
        layoutManager.delegate = layoutManager
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.codeBlocks = document.codeBlocks
        layoutManager.quoteBlocks = document.quoteBlocks
        layoutManager.tableBlocks = document.tableBlocks
        layoutManager.imageBlocks = document.imageBlocks
        layoutManager.hasThematicBreaks = document.hasThematicBreaks
        if let images {
            // As MarkdownContainerView sizes them, from what the store knew.
            let fontSize = request.fontSize
            layoutManager.imageBlockSize = { imageBlock, availableWidth in
                MarkdownImageMetrics.layoutSize(
                    of: imageBlock,
                    state: images.states[imageBlock.id] ?? .pending,
                    displayScale: images.displayScale,
                    fontSize: fontSize,
                    availableWidth: availableWidth
                )
            }
        }
        storage.setAttributedString(document.attributedString)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)

        // As MarkdownPlainTextView does: own cell blocks, sized to this width.
        let tables = document.tableBlocks.filter { !$0.columnWidthLimits.isEmpty }
        storage.copyCellBlocks(of: tables)
        for table in tables {
            _ = storage.fitColumns(of: table, to: width)
        }

        layoutManager.ensureLayout(for: container)
        let usedRect = layoutManager.usedRect(for: container)

        self.request = request
        self.document = document
        self.storage = storage
        self.layoutManager = layoutManager
        self.container = container
        self.size = CGSize(width: width, height: ceil(usedRect.height))
        self.fittedTableIDs = Set(tables.map(\.id))
        self.images = images
    }
}

/// Keeps Markdown text laid out ahead of time, and the views of rows that
/// scrolled away, so showing a reply again or for the first time doesn't
/// typeset it on the main thread.
@MainActor
final class MarkdownPrefetcher {
    static let shared = MarkdownPrefetcher()

    /// The most text kept laid out ahead of time, in UTF-16 units of source.
    private static let preparedLimit = 3_000_000
    /// How many views of rows that scrolled away are kept, and how much text
    /// they may hold between them.
    private static let reusableViewLimit = 32
    private static let reusableLengthLimit = 600_000
    /// The most decoded image data loaded ahead of time for one loader, so
    /// texts with images can be laid out at their images' sizes. Half the
    /// image store's cache, leaving room for the images on screen.
    private static let imageBytesLimit = 96 * 1024 * 1024
    /// How long to wait for a text's images before laying it out without them.
    private static let imageLoadTimeout: Duration = .seconds(10)

    /// What the wanted texts are laid out in: the style, width, image
    /// loader and display scale of the latest view showing one.
    private struct Layout: Equatable {
        let style: MarkdownRenderStyle
        let width: CGFloat
        let imageLoader: MarkdownImageLoading
        let displayScale: CGFloat
    }

    /// The wanted texts of each `markdownPrefetch` view, first first.
    private var registrations: [UUID: [String]] = [:]
    private var wantedTexts: Set<String> = []
    private var layout: Layout?
    /// Decoded image data loaded ahead of time for the layout's loader.
    private var imageBytesLoaded = 0

    private var prepared: [String: MarkdownPreparedText] = [:]
    private var preparedLength = 0
    /// Wanted texts that can't be prepared, because their images didn't
    /// load in time or would go past the image limit.
    private var unpreparable: Set<String> = []
    /// Texts to prepare, the next one last.
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var pendingRebuild: Task<Void, Never>?

    private var reusableViews: [MarkdownRenderRequest: MarkdownContainerView] = [:]
    private var reusableOrder: [MarkdownRenderRequest] = []
    private var reusableLength = 0

    // MARK: - Registrations

    func want(_ texts: [String], for id: UUID) {
        registrations[id] = texts
        wantedTextsDidChange()
    }

    func stopWanting(for id: UUID) {
        guard registrations.removeValue(forKey: id) != nil else { return }
        wantedTextsDidChange()
    }

    private func wantedTextsDidChange() {
        wantedTexts = Set(registrations.values.joined())
        scheduleRebuild()
    }

    /// Notes how a view lays `request` out, which the other wanted texts
    /// are prepared in.
    func noteLayout(of request: MarkdownRenderRequest, width: CGFloat, imageLoader: MarkdownImageLoading, displayScale: CGFloat) {
        let next = Layout(style: request.style, width: width, imageLoader: imageLoader, displayScale: displayScale)
        guard layout != next, wantedTexts.contains(request.text) else { return }
        if layout?.imageLoader != imageLoader {
            imageBytesLoaded = 0
        }
        layout = next
        scheduleRebuild()
    }

    // MARK: - Preparing

    /// Rebuilds the queue once things settle, such as at the end of a live
    /// window resize, which changes the width every frame.
    private func scheduleRebuild() {
        pendingRebuild?.cancel()
        pendingRebuild = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            pendingRebuild = nil
            rebuildQueue()
        }
    }

    private func rebuildQueue() {
        for (text, entry) in prepared where !wantedTexts.contains(text) || !matchesLayout(entry) {
            prepared[text] = nil
            preparedLength -= text.utf16.count
        }
        unpreparable.formIntersection(wantedTexts)

        queue = []
        guard let layout else { return }
        var queued: Set<String> = []
        for texts in registrations.values {
            for text in texts where prepared[text] == nil && !unpreparable.contains(text) && queued.insert(text).inserted {
                let view = reusableViews[MarkdownRenderRequest(text: text, style: layout.style)]
                if view?.isLaidOut(atWidth: layout.width) != true { queue.append(text) }
            }
        }
        queue.reverse()
        startWorkerIfNeeded()
    }

    private func matchesLayout(_ entry: MarkdownPreparedText) -> Bool {
        guard let layout, entry.request.style == layout.style, entry.size.width == layout.width else { return false }
        guard let images = entry.images else { return true }
        return images.loaderID == layout.imageLoader.id && images.displayScale == layout.displayScale
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task(priority: .utility) {
            while let text = queue.last, let layout, preparedLength + text.utf16.count <= Self.preparedLimit {
                queue.removeLast()
                guard wantedTexts.contains(text), prepared[text] == nil else { continue }
                await prepare(text, in: layout)
            }
            worker = nil
        }
    }

    private func prepare(_ text: String, in layout: Layout) async {
        let request = MarkdownRenderRequest(text: text, style: layout.style)
        let width = layout.width
        let document: MarkdownRenderedDocument
        if let cached = MarkdownRenderCacheStore.shared.document(for: request) {
            document = cached
        } else {
            document = await MarkdownRenderScheduler.shared.document(for: request)
            MarkdownRenderCacheStore.shared.store(document, for: request)
        }
        var images: MarkdownPreparedImages?
        if !document.imageBlocks.isEmpty {
            images = await loadImages(of: document.imageBlocks, in: layout)
            guard images != nil else {
                unpreparable.insert(text)
                return
            }
        }
        let preparedText = await Task.detached(priority: .utility) { [images] in
            MarkdownPreparedText(request: request, document: document, width: width, images: images)
        }.value
        // The layout may have changed, or the text gone, while it was laid out.
        guard prepared[text] == nil, wantedTexts.contains(text), matchesLayout(preparedText) else { return }
        prepared[text] = preparedText
        preparedLength += text.utf16.count
    }

    /// Loads the images of a text about to be laid out, so it's laid out at
    /// their sizes rather than with placeholders that change size once a
    /// view loads them. Nil if they don't load in time, or loading them
    /// would go past the limit.
    private func loadImages(of imageBlocks: [MarkdownImageBlock], in layout: Layout) async -> MarkdownPreparedImages? {
        let store = MarkdownImageStore.shared
        let loader = layout.imageLoader
        let key = { (block: MarkdownImageBlock) in MarkdownImageKey(loaderID: loader.id, source: block.image.source) }
        let pending = Set(imageBlocks.map(key)).filter { store.layoutState(for: $0) == .pending }

        if !pending.isEmpty {
            guard imageBytesLoaded < Self.imageBytesLimit else { return nil }
            let wait = ImageWait(remaining: pending.count)
            let timeout = Task {
                try? await Task.sleep(for: Self.imageLoadTimeout)
                wait.finishAll()
            }
            await withCheckedContinuation { continuation in
                wait.continuation = continuation
                for key in pending {
                    store.load(key, using: loader.load, for: wait) { wait.finishOne() }
                }
            }
            timeout.cancel()
            if layout.imageLoader == self.layout?.imageLoader {
                imageBytesLoaded += pending.compactMap { store.asset(for: $0)?.cost }.reduce(0, +)
            }
            store.cancelLoads(for: wait)
        }

        var states: [Int: MarkdownImageStore.LayoutState] = [:]
        for block in imageBlocks {
            let state = store.layoutState(for: key(block))
            guard state != .pending else { return nil }
            states[block.id] = state
        }
        return MarkdownPreparedImages(loaderID: loader.id, states: states, displayScale: layout.displayScale)
    }

    /// Prepared text for `request`, as a view using `imageLoader` lays it
    /// out, which the caller adopts.
    func takePrepared(_ request: MarkdownRenderRequest, imageLoader: MarkdownImageLoading) -> MarkdownPreparedText? {
        guard let entry = prepared[request.text], entry.request == request,
              entry.images.map({ $0.loaderID == imageLoader.id }) ?? true else { return nil }
        prepared[request.text] = nil
        preparedLength -= request.text.utf16.count
        // Room for text the limit held back.
        startWorkerIfNeeded()
        return entry
    }

    // MARK: - Reusable views

    /// Keeps the view of a row that scrolled away, laid out, in case the row
    /// comes back.
    func reuseLater(_ view: MarkdownContainerView, showing request: MarkdownRenderRequest) {
        if reusableViews.updateValue(view, forKey: request) == nil {
            reusableOrder.append(request)
            reusableLength += request.text.utf16.count
        }
        while reusableOrder.count > Self.reusableViewLimit || (reusableLength > Self.reusableLengthLimit && reusableOrder.count > 1) {
            let evicted = reusableOrder.removeFirst()
            reusableViews[evicted] = nil
            reusableLength -= evicted.text.utf16.count
            // Laid out again ahead of time, if it's wanted.
            if evicted.style == layout?.style, prepared[evicted.text] == nil, wantedTexts.contains(evicted.text) {
                queue.append(evicted.text)
                startWorkerIfNeeded()
            }
        }
    }

    func reusableView(for request: MarkdownRenderRequest) -> MarkdownContainerView? {
        guard let view = reusableViews.removeValue(forKey: request) else { return nil }
        reusableOrder.removeAll { $0 == request }
        reusableLength -= request.text.utf16.count
        return view
    }
}

/// Waits for a text's image loads, as the owner of those loads.
@MainActor
private final class ImageWait {
    var remaining: Int
    var continuation: CheckedContinuation<Void, Never>?

    init(remaining: Int) {
        self.remaining = remaining
    }

    func finishOne() {
        remaining -= 1
        if remaining <= 0 { finishAll() }
    }

    func finishAll() {
        continuation?.resume()
        continuation = nil
    }
}
#endif
