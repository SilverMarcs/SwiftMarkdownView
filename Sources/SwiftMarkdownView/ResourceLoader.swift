//
//  ResourceLoader.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 27/09/2024.
//

import Foundation

class ResourceLoader {
    static let shared = ResourceLoader()
    private init() {}

    lazy var templateString: String = Self.loadResource(named: "template", withExtension: "html")
    lazy var clipboardScript: String = Self.loadResource(named: "script", withExtension: "js")
    lazy var defaultStyle: String = Self.loadResource(named: Self.styleSheetFileName, withExtension: "css")

    private var cachedHTMLString: String?
    private var cachedCustomStyles: [CodeBlockTheme: String] = [:]

    private static func loadResource(named name: String, withExtension ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            print("Failed to find resource: \(name).\(ext)")
            return ""
        }
        do {
            return try String(contentsOf: url)
        } catch {
            print("Failed to load resource \(name).\(ext): \(error)")
            return ""
        }
    }

    func getCachedHTMLString(with customTheme: CodeBlockTheme?) -> String {
        let customStyle = customTheme.map { getCustomStyle(for: $0) } ?? "atom"
        let combinedStyle = defaultStyle + "\n" + customStyle

        let replacements = [
            "PLACEHOLDER_SCRIPT": clipboardScript, // TODO: rename this variable it should not be clipboardScript
            "PLACEHOLDER_STYLESHEET": combinedStyle
        ]

        var htmlString = templateString
        for (placeholder, replacement) in replacements {
            htmlString = htmlString.replacingOccurrences(of: placeholder, with: replacement)
        }
        
        return htmlString
    }

    func getCustomStyle(for theme: CodeBlockTheme) -> String {
        if let cachedStyle = cachedCustomStyles[theme] {
            return cachedStyle
        }

        let style = Self.loadResource(named: theme.fileName, withExtension: "css")
        cachedCustomStyles[theme] = style
        return style
    }

    #if os(macOS) || targetEnvironment(macCatalyst)
    static let styleSheetFileName = "default-macOS"
    #else
    static let styleSheetFileName = "default-iOS"
    #endif
}
