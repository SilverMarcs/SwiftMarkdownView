//
//  CustomWebView.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 27/09/2024.
//

import WebKit
import SwiftUI

public class CustomWebView: WKWebView {
    var contentHeight: CGFloat = 0
    weak var coordinator: Coordinator?
    
    override public var intrinsicContentSize: CGSize {
        .init(width: super.intrinsicContentSize.width, height: contentHeight)
    }
    
    func recalculateContentHeight() {
        evaluateJavaScript("document.body.scrollHeight", in: nil, in: .page) { result in
            guard let contentHeight = try? result.get() as? Double else { return }
            self.contentHeight = contentHeight
            self.invalidateIntrinsicContentSize()
            
            #if os(macOS)
            self.superview?.needsLayout = true
            #else
            self.superview?.setNeedsLayout()
            #endif

            self.coordinator?.updateCalculatedHeight(self.contentHeight)
        }
    }
    
    #if os(macOS)
    override public func layout() {
        super.layout()
        recalculateContentHeight()
    }
    #else
    override public func layoutSubviews() {
        super.layoutSubviews()
        recalculateContentHeight()
    }
    #endif
    
    /// Disables scrolling.
    #if os(macOS)
    override public func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        nextResponder?.scrollWheel(with: event)
    }

    /// Removes "Reload" from the context menu.
    override public func willOpenMenu(_ menu: NSMenu, with _: NSEvent) {
        menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
    }
    
    override public func rightMouseDown(with event: NSEvent) {
        // Pass the event to the container view
        superview?.rightMouseDown(with: event)
    }
    #endif

    func updateMarkdownContent(_ markdownContent: String, highlightString: String, fontSize: CGFloat, codeBlockTheme: CodeBlockTheme) {
        let data: [String: Any] = [
            "markdownContent": markdownContent,
            "highlightString": highlightString,
            "fontSize": fontSize,
            "codeBlockTheme": codeBlockTheme.rawValue
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                callAsyncJavaScript("window.updateWithMarkdownContent(\(jsonString))", in: nil, in: .page) { _ in
                    self.recalculateContentHeight()
                }
            }
        } catch {
            print("Error converting to JSON: \(error)")
        }
    }
}

#if os(macOS)
class WebViewContainer: NSView {
    override func rightMouseDown(with event: NSEvent) {
        // Pass the event to the next responder (parent view)
        superview?.rightMouseDown(with: event)
    }
}
#endif
