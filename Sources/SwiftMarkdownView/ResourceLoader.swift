//
//  ResourceLoader.swift
//  markdown-webview
//
//  Created by Zabir Raihan on 27/09/2024.
//

import Foundation

class ResourceLoader {
    @MainActor static let shared = ResourceLoader()
    
    private init() {
        preProcessTemplates()
    }

    lazy var templateString: String = Self.loadResource(named: "template", withExtension: "html")
    lazy var clipboardScript: String = Self.loadResource(named: "script", withExtension: "js")
    lazy var defaultStyle: String = Self.loadResource(named: Self.styleSheetFileName, withExtension: "css")

    // Pre-processed templates cache
    private var preProcessedTemplates: [String: String] = [:]
    private var cachedCustomStyles: [CodeBlockTheme: String] = [:]

    private static func loadResource(named name: String, withExtension ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            print("Failed to find resource: \(name).\(ext)")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Failed to load resource \(name).\(ext): \(error)")
            return ""
        }
    }
    
    private func preProcessTemplates() {
        // Pre-process templates for all themes
        for theme in CodeBlockTheme.allCases {
            let customStyle = getCustomStyle(for: theme)
            let combinedStyle = defaultStyle + "\n" + customStyle
            
            let replacements = [
                "PLACEHOLDER_SCRIPT": clipboardScript,
                "PLACEHOLDER_STYLESHEET": combinedStyle
            ]
            
            var htmlString = templateString
            for (placeholder, replacement) in replacements {
                htmlString = htmlString.replacingOccurrences(of: placeholder, with: replacement)
            }
            
            preProcessedTemplates[theme.rawValue] = htmlString
        }
        
        // Also create a default template without custom theme
        let defaultCombinedStyle = defaultStyle + "\n" + getCustomStyle(for: .atom) // Use atom as default
        let defaultReplacements = [
            "PLACEHOLDER_SCRIPT": clipboardScript,
            "PLACEHOLDER_STYLESHEET": defaultCombinedStyle
        ]
        
        var defaultHtmlString = templateString
        for (placeholder, replacement) in defaultReplacements {
            defaultHtmlString = defaultHtmlString.replacingOccurrences(of: placeholder, with: replacement)
        }
        preProcessedTemplates["default"] = defaultHtmlString
    }

    func getCachedHTMLString(with customTheme: CodeBlockTheme?) -> String {
        let themeKey = customTheme?.rawValue ?? "default"
        return preProcessedTemplates[themeKey] ?? ""
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
