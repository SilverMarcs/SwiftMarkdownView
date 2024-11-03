//
//  Coordinator.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 27/09/2024.
//

import WebKit
import SwiftUI

public class Coordinator: NSObject, WKNavigationDelegate {
    let parent: MarkdownWebView
    let platformView: CustomWebView

    init(parent: MarkdownWebView) {
        self.parent = parent
        self.platformView = .init()
        // if we were to make the loading of html in bg thread, should we put showplaintxt func call before it or after it?
        platformView.showPlainTextContent(parent.markdownContent)
// start loading html
        let resources = ResourceLoader.shared
        let htmlString = resources.getCachedHTMLString()
        
        let baseURL = URL(string: parent.baseURL)
        platformView.loadHTMLString(htmlString, baseURL: baseURL)
// end loading html
        super.init()

        platformView.navigationDelegate = self

        platformView.setContentHuggingPriority(.required, for: .vertical)

        #if os(macOS)
        platformView.setValue(false, forKey: "drawsBackground")
        #else
        platformView.scrollView.isScrollEnabled = false
        platformView.isOpaque = false
        #endif
    }
    
    private func loadInitialHTML() {
        let resources = ResourceLoader.shared
        let htmlString = resources.getCachedHTMLString()
        
        let baseURL = URL(string: parent.baseURL)
        platformView.loadHTMLString(htmlString, baseURL: baseURL)
    }

    public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        let customWebView = webView as! CustomWebView
        customWebView.hidePlainTextContent()
        customWebView.updateMarkdownContent(parent.markdownContent, highlightString: parent.highlightString, fontSize: parent.fontSize)
    }
    
    public func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated {
            guard let url = navigationAction.request.url else { return .cancel }

            openPlatformURL(url)

            return .cancel
        } else {
            return .allow
        }
    }
    
    private func openPlatformURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        Task { await UIApplication.shared.open(url) }
        #endif
    }
}
