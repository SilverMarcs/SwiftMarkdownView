import SwiftUI
import WebKit

@available(macOS 11.0, iOS 14.0, *)
public struct SwiftMarkdownView: PlatformViewRepresentable {
    var markdownContent: String
    var calculatedHeight: Binding<CGFloat>?
    
    // Convert environment values to instance variables
    var fontSize: CGFloat
    var highlightString: String
    var baseURL: String
    var codeBlockTheme: CodeBlockTheme
    
    public init(
        _ markdownContent: String,
        calculatedHeight: Binding<CGFloat>? = nil,
        fontSize: CGFloat = 16,
        highlightString: String = "",
        baseURL: String = "",
        codeBlockTheme: CodeBlockTheme = .github
    ) {
        self.markdownContent = markdownContent
        self.calculatedHeight = calculatedHeight
        self.fontSize = fontSize
        self.highlightString = highlightString
        self.baseURL = baseURL
        self.codeBlockTheme = codeBlockTheme
    }

    // Rest of the implementation remains the same
    public func makeCoordinator() -> Coordinator { .init(parent: self) }
    
    public func updatePlatformView(_ platformView: CustomWebView, context _: Context) {
        guard !platformView.isLoading else { return }
        platformView.updateMarkdownContent(markdownContent, highlightString: highlightString, fontSize: fontSize, codeBlockTheme: codeBlockTheme)
    }

    #if os(macOS)
    public func makeNSView(context: Context) -> NSView {
        let container = WebViewContainer()
        let webView = context.coordinator.platformView
        container.addSubview(webView)
        
        // Set up constraints
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let webView = nsView.subviews.first as? CustomWebView {
            updatePlatformView(webView, context: context)
        }
    }
    #else
    public func makeUIView(context: Context) -> CustomWebView { context.coordinator.platformView }
    public func updateUIView(_ uiView: CustomWebView, context: Context) { updatePlatformView(uiView, context: context) }
    #endif
}

@available(macOS 11.0, iOS 14.0, *)
extension SwiftMarkdownView: Equatable {
    public static func == (lhs: SwiftMarkdownView, rhs: SwiftMarkdownView) -> Bool {
        return lhs.markdownContent == rhs.markdownContent &&
            lhs.fontSize == rhs.fontSize &&
            lhs.highlightString == rhs.highlightString &&
            lhs.baseURL == rhs.baseURL &&
            lhs.codeBlockTheme == rhs.codeBlockTheme
    }
}
