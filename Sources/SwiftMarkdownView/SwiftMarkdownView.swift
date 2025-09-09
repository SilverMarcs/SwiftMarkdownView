import SwiftUI
import WebKit

public struct SwiftMarkdownView: PlatformViewRepresentable {
    var markdownContent: String
    var calculatedHeight: Binding<CGFloat>?
    
    // Add new parameter
    var enableMarkdown: Bool
    
    var fontSize: CGFloat
    var highlightString: String
    var baseURL: String
    var codeBlockTheme: CodeBlockTheme
    
    public init(
        _ markdownContent: String,
        calculatedHeight: Binding<CGFloat>? = nil,
        enableMarkdown: Bool = true,
        fontSize: CGFloat = 16,
        highlightString: String = "",
        baseURL: String = "",
        codeBlockTheme: CodeBlockTheme = .atom
    ) {
        self.markdownContent = markdownContent
        self.calculatedHeight = calculatedHeight
        self.enableMarkdown = enableMarkdown
        self.fontSize = fontSize
        self.highlightString = highlightString
        self.baseURL = baseURL
        self.codeBlockTheme = codeBlockTheme
    }

    // Rest of the implementation remains the same
    public func makeCoordinator() -> Coordinator { .init(parent: self) }
    
    func updatePlatformView(_ platformView: CustomWebView, context _: Context) {
        guard !platformView.isLoading else { return }
        platformView.updateMarkdownContent(
            markdownContent,
            highlightString: highlightString,
            fontSize: fontSize,
            codeBlockTheme: codeBlockTheme,
            enableMarkdown: enableMarkdown
        )
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

#if os(macOS)
class WebViewContainer: NSView {
    override func rightMouseDown(with event: NSEvent) {
        // Pass the event to the next responder (parent view)
        unsafe superview?.rightMouseDown(with: event)
    }
}
#endif


// MARK: - Platform aliases

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif
