import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class MarkdownContainerView: PlatformView {
    fileprivate enum Layout {
        #if os(macOS)
        static let copyButtonInset: CGFloat = 4
        static let copyButtonSize: CGFloat = 23
        #else
        static let copyButtonInset: CGFloat = 6
        static let copyButtonSize: CGFloat = 18
        #endif
    }

    fileprivate let textView = MarkdownPlainTextView()
    fileprivate var currentWidth: CGFloat = 0
    fileprivate var lastReportedHeight: CGFloat = 0
    fileprivate var lastMeasuredSize: CGSize = .zero
    fileprivate var currentDocument: MarkdownRenderedDocument?
    fileprivate var currentRequest: MarkdownRenderRequest?
    fileprivate var currentThemeName: String?
    fileprivate var isShowingPlaceholder = false
    fileprivate var isShowingStreamedContent = false
    fileprivate var needsMeasurement = false
    fileprivate var cachedCodeBlockFrames: [(codeBlock: MarkdownCodeBlock, frame: CGRect)] = []

    var onThemeChange: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var imageLoader: MarkdownImageLoading = .default {
        didSet {
            guard imageLoader != oldValue else { return }
            imageLoaderDidChange()
        }
    }
    var onImageTap: (@MainActor (String) -> Void)? {
        didSet {
            for imageView in imageViews.values {
                imageView.onTap = onImageTap
            }
        }
    }

    private var imageViews: [Int: MarkdownImageView] = [:]
    /// The state each image block was last laid out in, by block ID, to tell
    /// when a load changes the layout.
    private var imageLayoutStates: [Int: MarkdownImageStore.LayoutState] = [:]
    private var imageDisplayScale: CGFloat = 0

    var codeBlockBackground: PlatformColor = .quaternarySystemFill {
        didSet {
            guard codeBlockBackground != oldValue else { return }
            textView.markdownLayoutManager.codeBlockBackgroundColor = codeBlockBackground
            for imageView in imageViews.values {
                imageView.fillColor = codeBlockBackground
            }
            #if !os(macOS)
            for tableView in tableViews.values {
                tableView.stripeColor = codeBlockBackground
            }
            for codeBlockView in codeBlockViews.values {
                codeBlockView.backgroundColor = codeBlockBackground
            }
            #endif
            #if os(macOS)
            textView.needsDisplay = true
            #else
            textView.setNeedsDisplay()
            #endif
        }
    }

    var codeTheme: MarkdownCodeTheme = .default {
        didSet {
            guard codeTheme != oldValue else { return }
            let newName = resolvedThemeName
            guard currentThemeName != newName else { return }
            currentThemeName = newName
            onThemeChange?(newName)
        }
    }

    fileprivate var widthConstraint: NSLayoutConstraint?

    #if os(macOS)
    var onOpenURL: ((URL) -> Void)? {
        didSet { textView.onOpenURL = onOpenURL }
    }

    private var codeBlockButtons: [Int: NSButton] = [:]
    private var hoveredCodeBlockID: Int?
    private var trackingArea: NSTrackingArea?
    #else
    private var codeBlockButtons: [Int: UIButton] = [:]
    private var tableViews: [Int: MarkdownTableView] = [:]
    private var codeBlockViews: [Int: MarkdownCodeBlockView] = [:]
    #endif

    // MARK: - Init

    #if os(macOS)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    override var isFlipped: Bool { true }
    #else
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        #if os(macOS)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        #else
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        // UITextView's selection menu defaults already include Copy.
        #endif

        textView.markdownTextContainer.lineFragmentPadding = 0
        textView.markdownTextContainer.widthTracksTextView = true
        textView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textView)

        textView.markdownLayoutManager.imageBlockSize = { [weak self] imageBlock, availableWidth in
            self?.layoutSize(of: imageBlock, availableWidth: availableWidth) ?? .zero
        }

        let widthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint
        ])
    }

    // MARK: - Layout

    #if os(macOS)
    override func layout() {
        super.layout()
        performLayoutPass()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        performLayoutPass()
    }
    #endif

    private func performLayoutPass() {
        let width = bounds.width > 0 ? bounds.width : currentWidth
        guard width > 0 else { return }

        recalculateIfNeeded(for: width, reportHeight: true)
        #if !os(macOS)
        layoutTableViews()
        layoutCodeBlockViews()
        #endif
        layoutCodeBlockButtons()
        layoutImageViews()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: lastMeasuredSize.width, height: lastMeasuredSize.height)
    }

    // MARK: - Appearance / theme

    #if os(macOS)
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        themeDidChangeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        imagesDidChangeVisibility()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        displayScaleDidChangeIfNeeded()
    }
    #else
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            themeDidChangeIfNeeded()
            setNeedsDisplay()
            textView.setNeedsDisplay()
        }
        if previousTraitCollection?.displayScale != traitCollection.displayScale {
            displayScaleDidChangeIfNeeded()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        imagesDidChangeVisibility()
    }
    #endif

    private func themeDidChangeIfNeeded() {
        let themeName = resolvedThemeName
        guard currentThemeName != themeName else { return }
        currentThemeName = themeName
        onThemeChange?(themeName)
    }

    var activeThemeName: String {
        currentThemeName ?? resolvedThemeName
    }

    private var resolvedThemeName: String {
        #if os(macOS)
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua: return codeTheme.dark
        default: return codeTheme.light
        }
        #else
        return traitCollection.userInterfaceStyle == .dark ? codeTheme.dark : codeTheme.light
        #endif
    }

    // MARK: - Public update API

    func showPlaceholder(text: String, fontSize: CGFloat, for request: MarkdownRenderRequest) {
        currentThemeName = request.themeName

        guard currentRequest != request || !isShowingPlaceholder else {
            recalculateIfNeeded(for: currentWidth, reportHeight: true)
            return
        }

        currentRequest = request
        currentDocument = nil
        isShowingPlaceholder = true
        display(document: .placeholder(text: text, fontSize: fontSize))
    }

    func apply(document: MarkdownRenderedDocument, for request: MarkdownRenderRequest, isStreamed: Bool = false) {
        currentThemeName = request.themeName

        guard currentRequest != request || isShowingPlaceholder || currentDocument == nil || isShowingStreamedContent else {
            recalculateIfNeeded(for: currentWidth, reportHeight: true)
            return
        }

        currentRequest = request
        currentDocument = document
        isShowingPlaceholder = false
        isShowingStreamedContent = isStreamed
        display(document: document)
    }

    func measuredSize(for width: CGFloat) -> CGSize {
        recalculateIfNeeded(for: width, reportHeight: false)
        return lastMeasuredSize
    }

    // MARK: - Rendering

    private func display(document: MarkdownRenderedDocument) {
        textView.update(document: document)
        syncCodeBlockButtons(with: document.codeBlocks)
        #if !os(macOS)
        syncTableViews(with: document.tableBlocks)
        syncCodeBlockViews(with: document.codeBlocks)
        #endif
        syncImageViews(with: document.imageBlocks)
        needsMeasurement = true
        #if os(macOS)
        needsLayout = true
        #else
        setNeedsLayout()
        #endif
        invalidateIntrinsicContentSize()
        recalculateIfNeeded(for: currentWidth, reportHeight: true)
    }

    private func recalculateIfNeeded(for width: CGFloat, reportHeight: Bool) {
        let resolvedWidth = ceil(width)
        guard resolvedWidth > 0 else { return }

        currentWidth = resolvedWidth

        guard needsMeasurement || lastMeasuredSize.width != resolvedWidth else {
            if reportHeight {
                reportHeightIfNeeded(lastMeasuredSize.height)
            }
            return
        }

        widthConstraint?.constant = resolvedWidth
        let measuredHeight = measureHeight()
        lastMeasuredSize = CGSize(width: resolvedWidth, height: measuredHeight)
        needsMeasurement = false

        if reportHeight {
            reportHeightIfNeeded(measuredHeight)
        }
    }

    private func measureHeight() -> CGFloat {
        guard currentWidth > 0 else { return 0 }

        textView.frame.size.width = currentWidth
        #if os(macOS)
        textView.markdownTextContainer.containerSize = CGSize(
            width: currentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.fitTables(to: currentWidth)
        #else
        textView.markdownTextContainer.size = CGSize(
            width: currentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        #endif
        textView.markdownLayoutManager.ensureLayout(for: textView.markdownTextContainer)
        let usedRect = textView.markdownLayoutManager.usedRect(for: textView.markdownTextContainer)
        return ceil(usedRect.height)
    }

    private func reportHeightIfNeeded(_ measuredHeight: CGFloat) {
        guard measuredHeight > 0, measuredHeight != lastReportedHeight else { return }
        lastReportedHeight = measuredHeight
        onHeightChange?(measuredHeight)
    }

    // MARK: - Copy buttons

    #if os(macOS)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredCodeBlock(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredCodeBlockID = nil
        updateCopyButtonVisibility()
    }
    #endif

    private func syncCodeBlockButtons(with codeBlocks: [MarkdownCodeBlock]) {
        let nextIDs = Set(codeBlocks.map(\.id))

        for id in codeBlockButtons.keys where !nextIDs.contains(id) {
            codeBlockButtons[id]?.removeFromSuperview()
            codeBlockButtons[id] = nil
        }

        for codeBlock in codeBlocks where codeBlockButtons[codeBlock.id] == nil {
            let button = makeCopyButton(for: codeBlock.id)
            addSubview(button)
            codeBlockButtons[codeBlock.id] = button
        }
    }

    #if os(macOS)
    private func makeCopyButton(for id: Int) -> NSButton {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Copy code"
            ) ?? NSImage(),
            target: self,
            action: #selector(copyCodeBlock(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(String(id))
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        return button
    }
    #else
    private func makeCopyButton(for id: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        config.image = UIImage(systemName: "clipboard", withConfiguration: symbolConfig)
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config)
        button.tag = id
        button.addTarget(self, action: #selector(copyCodeBlockTouchUp(_:)), for: .touchUpInside)
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = true
        button.accessibilityLabel = "Copy code"
        return button
    }
    #endif

    private func layoutCodeBlockButtons() {
        cachedCodeBlockFrames = textView.codeBlockFrames()
        let codeBlockRects = Dictionary(
            uniqueKeysWithValues: cachedCodeBlockFrames.map { ($0.codeBlock.id, $0.frame) }
        )

        for (id, button) in codeBlockButtons {
            #if os(macOS)
            let overlaidFrame: CGRect? = nil
            #else
            let overlaidFrame = codeBlockViews[id].flatMap { $0.isHidden ? nil : $0.frame }
            #endif
            guard let convertedRect = overlaidFrame ?? codeBlockRects[id].map({ textView.convert($0, to: self) }) else {
                button.isHidden = true
                continue
            }

            button.frame = CGRect(
                x: convertedRect.maxX - Layout.copyButtonSize - Layout.copyButtonInset,
                y: convertedRect.maxY - Layout.copyButtonSize - Layout.copyButtonInset,
                width: Layout.copyButtonSize,
                height: Layout.copyButtonSize
            ).integral
            #if os(macOS)
            // visibility decided in updateCopyButtonVisibility based on hover
            #else
            button.isHidden = false
            #endif
        }

        #if os(macOS)
        updateCopyButtonVisibility()
        #endif
    }

    // MARK: - Images

    private var displayScale: CGFloat {
        #if os(macOS)
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        #else
        traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        #endif
    }

    /// The size an image block takes up: the image fitted to the width once
    /// its size is known, a placeholder until then, or a row with its label
    /// if it can't load.
    private func layoutSize(of imageBlock: MarkdownImageBlock, availableWidth: CGFloat) -> CGSize {
        let state = MarkdownImageStore.shared.layoutState(for: imageKey(imageBlock.image.source))
        imageLayoutStates[imageBlock.id] = state

        switch state {
        case .loaded(let pixelSize):
            let scale = max(displayScale, 1)
            imageDisplayScale = scale
            let naturalSize = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
            return MarkdownImageMetrics.fittedSize(natural: naturalSize, availableWidth: availableWidth)
        case .pending:
            return MarkdownImageMetrics.placeholderSize(availableWidth: availableWidth)
        case .failed:
            return MarkdownImageMetrics.failureSize(
                label: imageBlock.image.label,
                fontSize: currentRequest?.fontSize ?? 13,
                availableWidth: availableWidth
            )
        }
    }

    private func imageKey(_ source: String) -> MarkdownImageKey {
        MarkdownImageKey(loaderID: imageLoader.id, source: source)
    }

    private func syncImageViews(with imageBlocks: [MarkdownImageBlock]) {
        imageLayoutStates.removeAll()
        let nextIDs = Set(imageBlocks.map(\.id))

        for id in imageViews.keys where !nextIDs.contains(id) {
            imageViews[id]?.removeFromSuperview()
            imageViews[id] = nil
        }

        for imageBlock in imageBlocks {
            let imageView = imageViews[imageBlock.id] ?? {
                let view = MarkdownImageView(image: imageBlock.image)
                view.fillColor = codeBlockBackground
                view.onTap = onImageTap
                view.isHidden = true
                addSubview(view)
                imageViews[imageBlock.id] = view
                return view
            }()
            if imageView.image != imageBlock.image {
                imageView.image = imageBlock.image
                imageView.content = .loading
            }
            imageView.fontSize = currentRequest?.fontSize ?? 13
            refreshContent(of: imageView)
        }

        loadImagesIfNeeded()
    }

    /// Shows what the store has for an image view's source. A loaded image
    /// stays put even if the store has since evicted it.
    private func refreshContent(of imageView: MarkdownImageView) {
        if case .loaded = imageView.content { return }
        let store = MarkdownImageStore.shared
        let key = imageKey(imageView.image.source)
        if let asset = store.asset(for: key) {
            imageView.content = .loaded(asset)
        } else if store.hasFailed(key) {
            imageView.content = .failed
        } else if case .failed = imageView.content {
            imageView.content = .loading
        }
    }

    /// Loads images that aren't cached while the view is in a window, and
    /// cancels loads for images it no longer shows.
    private func loadImagesIfNeeded() {
        let store = MarkdownImageStore.shared
        guard window != nil else {
            store.cancelLoads(for: self)
            return
        }

        let keys = Set(imageViews.values.map { imageKey($0.image.source) })
        store.cancelLoads(for: self, keeping: keys)
        for key in keys where store.needsLoad(key) {
            store.load(key, using: imageLoader.load, for: self) { [weak self] in
                self?.imageDidLoad(key)
            }
        }
    }

    /// Images from another loader are different images, even at the same source.
    private func imageLoaderDidChange() {
        guard !imageViews.isEmpty else { return }
        for imageView in imageViews.values {
            imageView.content = .loading
            refreshContent(of: imageView)
        }
        loadImagesIfNeeded()
        relayoutStaleImages()
    }

    private func imagesDidChangeVisibility() {
        guard !imageViews.isEmpty else { return }
        for imageView in imageViews.values {
            refreshContent(of: imageView)
        }
        loadImagesIfNeeded()
        relayoutStaleImages()
    }

    private func imageDidLoad(_ key: MarkdownImageKey) {
        guard key.loaderID == imageLoader.id else { return }
        for imageView in imageViews.values where imageView.image.source == key.source {
            refreshContent(of: imageView)
        }
        relayoutStaleImages()
    }

    /// Lays out again the images whose size is known now but wasn't when
    /// they were last laid out. Each load changes the layout at most once.
    private func relayoutStaleImages() {
        let store = MarkdownImageStore.shared
        let staleBlocks = textView.markdownLayoutManager.imageBlocks.filter { block in
            guard let laidOutState = imageLayoutStates[block.id] else { return false }
            return laidOutState != store.layoutState(for: imageKey(block.image.source))
        }
        relayout(staleBlocks)
    }

    private func displayScaleDidChangeIfNeeded() {
        guard imageDisplayScale > 0, displayScale != imageDisplayScale else { return }
        imageDisplayScale = displayScale
        relayout(textView.markdownLayoutManager.imageBlocks)
    }

    private func relayout(_ imageBlocks: [MarkdownImageBlock]) {
        guard !imageBlocks.isEmpty else { return }
        textView.markdownLayoutManager.invalidateImageBlocks(imageBlocks)
        needsMeasurement = true
        #if os(macOS)
        needsLayout = true
        #else
        setNeedsLayout()
        #endif
        invalidateIntrinsicContentSize()
        recalculateIfNeeded(for: currentWidth, reportHeight: true)
    }

    private func layoutImageViews() {
        guard !imageViews.isEmpty else { return }

        var placedIDs = Set<Int>()
        for (imageBlock, frame) in textView.imageBlockFrames() {
            guard let imageView = imageViews[imageBlock.id] else { continue }
            imageView.frame = textView.convert(frame, to: self)
            imageView.isHidden = false
            placedIDs.insert(imageBlock.id)
        }
        for (id, imageView) in imageViews where !placedIDs.contains(id) {
            imageView.isHidden = true
        }
    }

    // MARK: - Tables

    #if !os(macOS)
    private func syncTableViews(with tableBlocks: [MarkdownTableBlock]) {
        let nextIDs = Set(tableBlocks.map(\.id))

        for id in tableViews.keys where !nextIDs.contains(id) {
            tableViews[id]?.removeFromSuperview()
            tableViews[id] = nil
        }

        for tableBlock in tableBlocks {
            let tableView = tableViews[tableBlock.id] ?? {
                let view = MarkdownTableView()
                view.stripeColor = codeBlockBackground
                insertSubview(view, aboveSubview: textView)
                tableViews[tableBlock.id] = view
                return view
            }()
            tableView.tableLayout = tableBlock.layout
        }
    }

    private func syncCodeBlockViews(with codeBlocks: [MarkdownCodeBlock]) {
        let nextIDs = Set(codeBlocks.compactMap { $0.layout == nil ? nil : $0.id })

        for id in codeBlockViews.keys where !nextIDs.contains(id) {
            codeBlockViews[id]?.removeFromSuperview()
            codeBlockViews[id] = nil
        }

        for codeBlock in codeBlocks {
            guard let layout = codeBlock.layout else { continue }
            let codeBlockView = codeBlockViews[codeBlock.id] ?? {
                let view = MarkdownCodeBlockView()
                view.backgroundColor = codeBlockBackground
                insertSubview(view, aboveSubview: textView)
                codeBlockViews[codeBlock.id] = view
                return view
            }()
            codeBlockView.codeLayout = layout
        }
    }

    private func layoutCodeBlockViews() {
        guard !codeBlockViews.isEmpty else { return }

        for codeBlockView in codeBlockViews.values {
            codeBlockView.isHidden = true
        }
        for (codeBlock, lineRect) in textView.overlaidCodeBlockFrames() {
            guard let codeBlockView = codeBlockViews[codeBlock.id], let layout = codeBlock.layout else { continue }
            let convertedRect = textView.convert(lineRect, to: self)
            codeBlockView.isHidden = false
            codeBlockView.frame = CGRect(
                x: convertedRect.minX,
                y: convertedRect.minY,
                width: bounds.width - convertedRect.minX,
                height: layout.height
            )
        }
    }

    private func layoutTableViews() {
        guard !tableViews.isEmpty else { return }

        for (tableBlock, lineRect) in textView.tableBlockFrames() {
            guard let tableView = tableViews[tableBlock.id], let layout = tableBlock.layout else { continue }
            let convertedRect = textView.convert(lineRect, to: self)
            tableView.frame = CGRect(
                x: convertedRect.minX,
                y: convertedRect.minY,
                width: min(layout.width, bounds.width - convertedRect.minX),
                height: layout.height
            )
        }
    }
    #endif

    #if os(macOS)
    private func updateHoveredCodeBlock(for event: NSEvent) {
        let locationInTextView = textView.convert(event.locationInWindow, from: nil)
        var newHoveredID: Int?

        for (codeBlock, frame) in cachedCodeBlockFrames {
            if frame.contains(locationInTextView) {
                newHoveredID = codeBlock.id
                break
            }
        }

        guard hoveredCodeBlockID != newHoveredID else { return }
        hoveredCodeBlockID = newHoveredID
        updateCopyButtonVisibility()
    }

    private func updateCopyButtonVisibility() {
        for (id, button) in codeBlockButtons {
            button.isHidden = id != hoveredCodeBlockID
        }
    }

    @objc
    private func copyCodeBlock(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let codeBlockID = Int(identifier),
              let codeBlock = currentDocument?.codeBlocks.first(where: { $0.id == codeBlockID }) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeBlock.content, forType: .string)
    }
    #else
    @objc
    private func copyCodeBlockTouchUp(_ sender: UIButton) {
        guard let codeBlock = currentDocument?.codeBlocks.first(where: { $0.id == sender.tag }) else {
            return
        }
        UIPasteboard.general.string = codeBlock.content
    }
    #endif
}
