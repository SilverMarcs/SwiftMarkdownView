//
//  Coordinator.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 27/09/2024.
//

import WebKit
import SwiftUI

public class Coordinator: NSObject, WKNavigationDelegate {
    let parent: SwiftMarkdownView
    let platformView: CustomWebView

    init(parent: SwiftMarkdownView) {
        self.parent = parent
        self.platformView = .init()
        super.init()
        
        platformView.coordinator = self
        
        let resources = ResourceLoader.shared
        let htmlString = resources.getCachedHTMLString(with: parent.codeBlockTheme)
        let baseURL = URL(string: parent.baseURL)
        platformView.loadHTMLString(htmlString, baseURL: baseURL)
    
        platformView.navigationDelegate = self
        platformView.setContentHuggingPriority(.required, for: .vertical)

        #if os(macOS)
        platformView.setValue(false, forKey: "drawsBackground")
        #else
        platformView.scrollView.isScrollEnabled = false
        platformView.isOpaque = false
        #endif
    }
    
    func updateCalculatedHeight(_ height: CGFloat) {
        DispatchQueue.main.async {
            self.parent.calculatedHeight?.wrappedValue = height
        }
    }

    public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        let customWebView = webView as! CustomWebView
        customWebView.updateMarkdownContent(parent.markdownContent, highlightString: parent.highlightString, fontSize: parent.fontSize, codeBlockTheme: parent.codeBlockTheme, enableMarkdown: parent.enableMarkdown)
    }
    
    public func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated {
            guard let url = navigationAction.request.url else { return .cancel }
            
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            Task { await UIApplication.shared.open(url) }
            #endif
            
            return .cancel
        } else {
            return .allow
        }
    }
}
