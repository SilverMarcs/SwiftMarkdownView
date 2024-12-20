//
//  MarkdownFontSizeKey.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 16/10/2024.
//


import SwiftUI

private struct MarkdownFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 13
}

private struct MarkdownHighlightStringKey: EnvironmentKey {
    static let defaultValue: String = ""
}

private struct MarkdownBaseURLKey: EnvironmentKey {
    static let defaultValue: String = "Web Content"
}

private struct CodeBlockThemeKey: EnvironmentKey {
    static let defaultValue: CodeBlockTheme = .atom
}

extension EnvironmentValues {
    var markdownFontSize: CGFloat {
        get { self[MarkdownFontSizeKey.self] }
        set { self[MarkdownFontSizeKey.self] = newValue }
    }
    
    var markdownHighlightString: String {
        get { self[MarkdownHighlightStringKey.self] }
        set { self[MarkdownHighlightStringKey.self] = newValue }
    }
    
    var markdownBaseURL: String {
        get { self[MarkdownBaseURLKey.self] }
        set { self[MarkdownBaseURLKey.self] = newValue }
    }

    var codeBlockTheme: CodeBlockTheme {
        get { self[CodeBlockThemeKey.self] }
        set { self[CodeBlockThemeKey.self] = newValue }
    }
}

extension View {
    public func markdownFontSize(_ size: CGFloat) -> some View {
        environment(\.markdownFontSize, size)
    }
    
    public func markdownHighlightString(_ string: String) -> some View {
        environment(\.markdownHighlightString, string)
    }
    
    public func markdownBaseURL(_ url: String) -> some View {
        environment(\.markdownBaseURL, url)
    }
    
    public func codeBlockTheme(_ theme: CodeBlockTheme) -> some View {
        environment(\.codeBlockTheme, theme)
    }
}
