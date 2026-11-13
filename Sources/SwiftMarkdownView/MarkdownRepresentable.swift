import SwiftUI

/// Renders a Markdown view's text off the main thread, one render at a time.
///
/// Text that changes while a render runs waits for it rather than cancelling
/// it: a render that finishes is shown whenever it's newer than what's on
/// screen, then the latest text renders next. A streaming reply is formatted
/// as fast as renders allow, with no delay, and until a render lands the view
/// keeps showing the last formatted text.
@MainActor
final class MarkdownRepresentableCoordinator {
    /// The text the view should show.
    private var currentRequest: MarkdownRenderRequest?
    /// The text the view shows, rendered.
    private var shownRequest: MarkdownRenderRequest?
    private var renderTask: Task<Void, Never>?
    private weak var view: MarkdownContainerView?

    deinit {
        renderTask?.cancel()
    }

    var isRendering: Bool { renderTask != nil }

    func update(
        view: MarkdownContainerView,
        text: String,
        fontSize: CGFloat,
        themeName: String,
        codeBlockBackground: Color
    ) {
        view.codeBlockBackground = PlatformColor(codeBlockBackground)
        self.view = view

        let request = MarkdownRenderRequest(
            text: text,
            fontSize: fontSize,
            themeName: themeName,
            codeBlockBackground: codeBlockBackground
        )
        currentRequest = request

        // A reused or prepared view already shows it.
        if view.isShowing(request) {
            shownRequest = request
            return
        }

        if let cachedDocument = MarkdownRenderCacheStore.shared.document(for: request) {
            show(cachedDocument, for: request, in: view)
            return
        }

        if shownRequest == nil {
            view.showPlaceholder(text: text, fontSize: fontSize, for: request)
        }
        renderNextIfIdle()
    }

    private func renderNextIfIdle() {
        guard renderTask == nil, let request = currentRequest, request != shownRequest else { return }
        renderTask = Task { [weak self] in
            let document = await MarkdownRenderScheduler.shared.document(for: request)
            guard !Task.isCancelled, let self else { return }
            MarkdownRenderCacheStore.shared.store(document, for: request)
            renderTask = nil
            if let view, let currentRequest, isWorthShowing(request, while: currentRequest) {
                show(document, for: request, in: view)
            }
            renderNextIfIdle()
        }
    }

    /// Whether a finished render of `request` should replace what's shown
    /// while the view wants `current`: it's `current` or an earlier part of the
    /// same growing text, and no older than what's on screen.
    private func isWorthShowing(_ request: MarkdownRenderRequest, while current: MarkdownRenderRequest) -> Bool {
        guard request.hasSameStyle(as: current), current.text.hasPrefix(request.text) else { return false }
        guard let shownRequest, shownRequest.hasSameStyle(as: current), current.text.hasPrefix(shownRequest.text) else { return true }
        return request.text.utf16.count > shownRequest.text.utf16.count
    }

    private func show(_ document: MarkdownRenderedDocument, for request: MarkdownRenderRequest, in view: MarkdownContainerView) {
        shownRequest = request
        view.apply(document: document, for: request)
    }
}

private extension MarkdownRenderRequest {
    func hasSameStyle(as other: MarkdownRenderRequest) -> Bool {
        fontSize == other.fontSize && themeName == other.themeName && codeBlockBackground == other.codeBlockBackground
    }
}

#if os(macOS)
import AppKit

struct MarkdownRepresentable: NSViewRepresentable {
    let text: String
    let onHeightChange: ((CGFloat) -> Void)?

    @Environment(\.openURL) private var openURL
    @Environment(\.markdownFontSize) private var fontSize
    @Environment(\.markdownCodeBlockBackground) private var codeBlockBackground
    @Environment(\.markdownCodeTheme) private var codeTheme
    @Environment(\.markdownImageLoader) private var imageLoader
    @Environment(\.markdownImageTapAction) private var imageTapAction

    func makeCoordinator() -> MarkdownRepresentableCoordinator {
        MarkdownRepresentableCoordinator()
    }

    func makeNSView(context: Context) -> MarkdownContainerView {
        // The view of a row that scrolled away, or text laid out ahead of
        // time, saves typesetting it on the main thread.
        let themeName = context.environment.colorScheme == .dark ? codeTheme.dark : codeTheme.light
        let request = MarkdownRenderRequest(text: text, fontSize: fontSize, themeName: themeName, codeBlockBackground: codeBlockBackground)
        let prefetcher = MarkdownPrefetcher.shared
        if let view = prefetcher.reusableView(for: request) {
            return view
        }
        if let prepared = prefetcher.takePrepared(request, imageLoader: imageLoader) {
            MarkdownRenderCacheStore.shared.store(prepared.document, for: request)
            return MarkdownContainerView(prepared: prepared)
        }
        return MarkdownContainerView()
    }

    static func dismantleNSView(_ nsView: MarkdownContainerView, coordinator: MarkdownRepresentableCoordinator) {
        // A render still on its way belongs to this view's old owner.
        guard let request = nsView.shownRequest, !coordinator.isRendering else { return }
        nsView.resetForReuse()
        MarkdownPrefetcher.shared.reuseLater(nsView, showing: request)
    }

    func updateNSView(_ nsView: MarkdownContainerView, context: Context) {
        nsView.codeTheme = codeTheme
        wireCallbacks(view: nsView, coordinator: context.coordinator)
        context.coordinator.update(
            view: nsView,
            text: text,
            fontSize: fontSize,
            themeName: nsView.activeThemeName,
            codeBlockBackground: codeBlockBackground
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MarkdownContainerView,
        context: Context
    ) -> CGSize? {
        // A view can't lay text out at an unlimited width, as when a scroll
        // view asks for its ideal size.
        guard let width = proposal.width, width.isFinite else { return nil }
        return nsView.measuredSize(for: width)
    }

    private func wireCallbacks(view: MarkdownContainerView, coordinator: MarkdownRepresentableCoordinator) {
        view.imageLoader = imageLoader
        view.onImageTap = imageTapAction?.action
        view.onOpenURL = { [openURL] url in openURL(url) }
        let text = self.text
        let fontSize = self.fontSize
        let codeBlockBackground = self.codeBlockBackground
        let heightHandler = self.onHeightChange
        view.onThemeChange = { [weak view] themeName in
            guard let view else { return }
            coordinator.update(
                view: view,
                text: text,
                fontSize: fontSize,
                themeName: themeName,
                codeBlockBackground: codeBlockBackground
            )
        }
        view.onHeightChange = { newHeight in
            heightHandler?(newHeight)
        }
    }
}

#else
import UIKit

struct MarkdownRepresentable: UIViewRepresentable {
    let text: String
    let onHeightChange: ((CGFloat) -> Void)?

    @Environment(\.markdownFontSize) private var fontSize
    @Environment(\.markdownCodeBlockBackground) private var codeBlockBackground
    @Environment(\.markdownCodeTheme) private var codeTheme
    @Environment(\.markdownImageLoader) private var imageLoader
    @Environment(\.markdownImageTapAction) private var imageTapAction

    func makeCoordinator() -> MarkdownRepresentableCoordinator {
        MarkdownRepresentableCoordinator()
    }

    func makeUIView(context: Context) -> MarkdownContainerView {
        MarkdownContainerView()
    }

    func updateUIView(_ uiView: MarkdownContainerView, context: Context) {
        uiView.codeTheme = codeTheme
        wireCallbacks(view: uiView, coordinator: context.coordinator)
        context.coordinator.update(
            view: uiView,
            text: text,
            fontSize: fontSize,
            themeName: uiView.activeThemeName,
            codeBlockBackground: codeBlockBackground
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MarkdownContainerView,
        context: Context
    ) -> CGSize? {
        // A view can't lay text out at an unlimited width, as when a scroll
        // view asks for its ideal size.
        guard let width = proposal.width, width.isFinite else { return nil }
        return uiView.measuredSize(for: width)
    }

    private func wireCallbacks(view: MarkdownContainerView, coordinator: MarkdownRepresentableCoordinator) {
        view.imageLoader = imageLoader
        view.onImageTap = imageTapAction?.action
        let text = self.text
        let fontSize = self.fontSize
        let codeBlockBackground = self.codeBlockBackground
        let heightHandler = self.onHeightChange
        view.onThemeChange = { [weak view] themeName in
            guard let view else { return }
            coordinator.update(
                view: view,
                text: text,
                fontSize: fontSize,
                themeName: themeName,
                codeBlockBackground: codeBlockBackground
            )
        }
        view.onHeightChange = { newHeight in
            heightHandler?(newHeight)
        }
    }
}

#endif
