import SwiftUI

@MainActor
final class MarkdownRepresentableCoordinator {
    private let streamingRenderDelay: Duration = .milliseconds(180)
    private var currentRequest: MarkdownRenderRequest?
    private var pendingRenderRequest: MarkdownRenderRequest?
    private var lastRenderedRequest: MarkdownRenderRequest?
    private var lastRenderedDocument: MarkdownRenderedDocument?
    private var streamingBuffer: NSMutableAttributedString?
    private var lastStreamedTextLength: Int = 0
    private var renderTask: Task<Void, Never>?

    deinit {
        renderTask?.cancel()
    }

    func update(
        view: MarkdownContainerView,
        text: String,
        fontSize: CGFloat,
        themeName: String,
        codeBlockBackground: Color
    ) {
        view.codeBlockBackground = PlatformColor(codeBlockBackground)

        let request = MarkdownRenderRequest(
            text: text,
            fontSize: fontSize,
            themeName: themeName,
            codeBlockBackground: codeBlockBackground
        )

        if let cachedDocument = MarkdownRenderCacheStore.shared.document(for: request) {
            renderTask?.cancel()
            renderTask = nil
            pendingRenderRequest = nil
            applyRenderedDocument(cachedDocument, for: request, to: view)
            return
        }

        let isAppendingUpdate = isPrefixExtension(of: request)

        if isAppendingUpdate, let streamedDocument = streamedDocument(for: request) {
            currentRequest = request
            view.apply(document: streamedDocument, for: request, isStreamed: true)
        } else if lastRenderedDocument == nil {
            currentRequest = request
            view.showPlaceholder(text: text, fontSize: fontSize, for: request)
        } else {
            currentRequest = request
        }

        guard pendingRenderRequest != request || !isAppendingUpdate else { return }

        let renderDelay: Duration = isAppendingUpdate ? streamingRenderDelay : .zero
        pendingRenderRequest = request
        renderTask?.cancel()
        renderTask = Task { [weak view] in
            if renderDelay > .zero {
                try? await Task.sleep(for: renderDelay)
            }

            guard !Task.isCancelled else { return }
            let document = await MarkdownRenderScheduler.shared.document(for: request)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                MarkdownRenderCacheStore.shared.store(document, for: request)

                guard let view, self.currentRequest == request else { return }
                self.pendingRenderRequest = nil
                self.applyRenderedDocument(document, for: request, to: view)
            }
        }
    }

    private func streamedDocument(for request: MarkdownRenderRequest) -> MarkdownRenderedDocument? {
        guard let lastRenderedRequest,
              let lastRenderedDocument,
              lastRenderedRequest.fontSize == request.fontSize,
              lastRenderedRequest.themeName == request.themeName,
              lastRenderedRequest.codeBlockBackground == request.codeBlockBackground,
              request.text.hasPrefix(lastRenderedRequest.text),
              request.text != lastRenderedRequest.text else {
            streamingBuffer = nil
            return nil
        }

        if streamingBuffer == nil {
            streamingBuffer = NSMutableAttributedString(attributedString: lastRenderedDocument.attributedString)
            lastStreamedTextLength = lastRenderedRequest.text.count
        }

        let newText = String(request.text.dropFirst(lastStreamedTextLength))
        if !newText.isEmpty {
            streamingBuffer!.append(MarkdownRenderedDocument.plainTextFragment(newText, fontSize: request.fontSize))
            lastStreamedTextLength = request.text.count
        }

        return MarkdownRenderedDocument(
            attributedString: NSAttributedString(attributedString: streamingBuffer!),
            codeBlocks: lastRenderedDocument.codeBlocks,
            quoteBlocks: lastRenderedDocument.quoteBlocks,
            tableBlocks: lastRenderedDocument.tableBlocks,
            hasThematicBreaks: lastRenderedDocument.hasThematicBreaks
        )
    }

    private func isPrefixExtension(of request: MarkdownRenderRequest) -> Bool {
        guard let lastRenderedRequest else { return false }
        return lastRenderedRequest.fontSize == request.fontSize &&
            lastRenderedRequest.themeName == request.themeName &&
            lastRenderedRequest.codeBlockBackground == request.codeBlockBackground &&
            request.text.hasPrefix(lastRenderedRequest.text) &&
            request.text != lastRenderedRequest.text
    }

    private func applyRenderedDocument(
        _ document: MarkdownRenderedDocument,
        for request: MarkdownRenderRequest,
        to view: MarkdownContainerView
    ) {
        streamingBuffer = nil
        currentRequest = request
        lastRenderedRequest = request
        lastRenderedDocument = document
        view.apply(document: document, for: request)
    }
}

#if os(macOS)
import AppKit

struct MarkdownRepresentable: NSViewRepresentable {
    let text: String
    let onHeightChange: ((CGFloat) -> Void)?

    @Environment(\.markdownFontSize) private var fontSize
    @Environment(\.markdownCodeBlockBackground) private var codeBlockBackground
    @Environment(\.markdownCodeTheme) private var codeTheme

    func makeCoordinator() -> MarkdownRepresentableCoordinator {
        MarkdownRepresentableCoordinator()
    }

    func makeNSView(context: Context) -> MarkdownContainerView {
        MarkdownContainerView()
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
        guard let width = proposal.width else { return nil }
        return nsView.measuredSize(for: width)
    }

    private func wireCallbacks(view: MarkdownContainerView, coordinator: MarkdownRepresentableCoordinator) {
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
        guard let width = proposal.width else { return nil }
        return uiView.measuredSize(for: width)
    }

    private func wireCallbacks(view: MarkdownContainerView, coordinator: MarkdownRepresentableCoordinator) {
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
