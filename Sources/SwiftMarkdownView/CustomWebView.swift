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
    
    // Add caching for height calculation
    private var lastContentHash: Int = 0
    private var cachedHeight: CGFloat = 0
    
    override public var intrinsicContentSize: CGSize {
        .init(width: super.intrinsicContentSize.width, height: contentHeight)
    }
    
    /// Disables scrolling.
    #if os(macOS)
    override public func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        unsafe nextResponder?.scrollWheel(with: event)
    }

    /// Removes "Reload" from the context menu.
    override public func willOpenMenu(_ menu: NSMenu, with _: NSEvent) {
        menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
    }
    
    override public func rightMouseDown(with event: NSEvent) {
        // Pass the event to the container view
        unsafe superview?.rightMouseDown(with: event)
    }
    #endif

    func updateMarkdownContent(_ markdownContent: String, highlightString: String, fontSize: CGFloat, codeBlockTheme: CodeBlockTheme, enableMarkdown: Bool) {
        // Create a hash of the content that affects height
        let contentForHashing = "\(markdownContent)\(fontSize)\(enableMarkdown)"
        let currentContentHash = contentForHashing.hashValue
        
        let data: [String: Any] = [
            "markdownContent": markdownContent,
            "highlightString": highlightString,
            "fontSize": fontSize,
            "codeBlockTheme": codeBlockTheme.rawValue,
            "enableMarkdown": enableMarkdown
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                callAsyncJavaScript("window.updateWithMarkdownContent(\(jsonString))", in: nil, in: .page)
            }
        } catch {
            print("Error converting to JSON: \(error)")
        }
        
        // Only recalculate height if content that affects height has changed
        if currentContentHash != lastContentHash {
            evaluateJavaScript("document.body.scrollHeight", in: nil, in: .page) { result in
                guard let newHeight = try? result.get() as? Double else { return }
                let newHeightCGFloat = CGFloat(newHeight)
                
                // Only update if height actually changed
                if abs(newHeightCGFloat - self.cachedHeight) > 1.0 { // 1pt tolerance
                    self.cachedHeight = newHeightCGFloat
                    self.contentHeight = newHeightCGFloat
                    self.invalidateIntrinsicContentSize()
                    self.coordinator?.updateCalculatedHeight(self.contentHeight)
                }
            }
            lastContentHash = currentContentHash
        }
    }
}
