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
    var skeletonView: SkeletonView?
    
    override public var intrinsicContentSize: CGSize {
        .init(width: super.intrinsicContentSize.width, height: contentHeight)
    }
    
    func showPlainTextContent(_ content: String, renderSkeleton: Bool) {
        let layoutManager = NSLayoutManager()
        #if os(macOS)
        let textContainer = NSTextContainer(containerSize: CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        #else
        let textContainer = NSTextContainer(size: CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        #endif
        let textStorage = NSTextStorage(string: content)
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        textContainer.lineFragmentPadding = 0
        
        let font = PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize + 5) // extra size since webview text includes styling that takes up more space
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        
        layoutManager.ensureLayout(for: textContainer)
        
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height
        
        // Update the content height and invalidate intrinsic content size
        contentHeight = newHeight
        invalidateIntrinsicContentSize()
        
        // Create and add the skeleton layer TODO: explore if this is necessary
        if renderSkeleton {
            DispatchQueue.main.async {
                self.showSkeletonView()
            }
        }
        
        // Notify the parent view that our size has changed
        #if os(macOS)
        superview?.needsLayout = true
        #else
        superview?.setNeedsLayout()
        #endif
    }
    
    func showSkeletonView() {
        if skeletonView == nil {
            skeletonView = SkeletonView(frame: bounds)
            addSubview(skeletonView!)
        }
        
        #if os(macOS)
        skeletonView?.alphaValue = 1.0 // Ensure full opacity when showing
        #else
        skeletonView?.alpha = 1.0
        #endif
        
        skeletonView?.updateSkeleton(for: contentHeight)
        skeletonView?.isHidden = false
    }
    
    func hideSkeletonView() {
        guard let skeletonView = skeletonView, !skeletonView.isHidden else { return }
        
        skeletonView.fadeOut {
            skeletonView.isHidden = true
             skeletonView.removeFromSuperview()
//             self.skeletonView = nil
        }
    }
    
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
    #endif

    func updateMarkdownContent(_ markdownContent: String, highlightString: String, fontSize: CGFloat, renderSkeleton: Bool, codeBlockTheme: CodeBlockTheme) {
        let data: [String: Any] = [
            "markdownContent": markdownContent,
            "highlightString": highlightString,
            "fontSize": fontSize,
            "codeBlockTheme": codeBlockTheme.rawValue
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                callAsyncJavaScript("window.updateWithMarkdownContent(\(jsonString))", in: nil, in: .page, completionHandler: nil)
            }
        } catch {
            print("Error converting to JSON: \(error)")
        }
        
        evaluateJavaScript("document.body.scrollHeight", in: nil, in: .page) { result in
            guard let contentHeight = try? result.get() as? Double else { return }
            self.contentHeight = contentHeight
            self.invalidateIntrinsicContentSize()
        }
    }
}
