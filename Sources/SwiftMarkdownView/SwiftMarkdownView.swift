import SwiftUI

/// Highlight.js theme names used for fenced code blocks.
///
/// `light` is applied when the view's appearance resolves to light, `dark` when
/// it resolves to dark. Names match the stylesheets bundled with Highlightr.
/// Browse the catalog at:
/// https://github.com/highlightjs/highlight.js/tree/main/src/styles
public struct MarkdownCodeTheme: Hashable, Sendable {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    public static let `default` = MarkdownCodeTheme(light: "atom-one-light", dark: "atom-one-dark")
}

/// A SwiftUI view that renders a Markdown string with syntax-highlighted code
/// blocks, tables, blockquotes, lists, and headings.
///
/// Configure with the provided view modifiers:
/// ```swift
/// SwiftMarkdownView(text) { height in
///     // optional measured-height callback
/// }
/// .markdownFontSize(17)
/// .markdownCodeBlockBackground(Color(.quaternarySystemFill))
/// .markdownCodeTheme(light: "atom-one-light", dark: "atom-one-dark")
/// ```
public struct SwiftMarkdownView: View {
    let content: String
    let onHeightChange: ((CGFloat) -> Void)?

    /// Create a Markdown view.
    /// - Parameters:
    ///   - content: The Markdown source to render.
    ///   - onHeightChange: Optional callback receiving the measured content
    ///     height whenever it changes. Useful for sizing a parent container.
    public init(_ content: String, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.content = content
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        MarkdownRepresentable(text: content, onHeightChange: onHeightChange)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var markdownFontSize: CGFloat = 13
    @Entry var markdownCodeBlockBackground: Color = Color(PlatformColor.quaternarySystemFill)
    @Entry var markdownCodeTheme: MarkdownCodeTheme = .default
}

// MARK: - Modifiers

public extension View {
    /// Sets the body font size for rendered Markdown.
    ///
    /// The code font derives from this value (one point smaller, monospaced).
    func markdownFontSize(_ size: CGFloat) -> some View {
        environment(\.markdownFontSize, size)
    }

    /// Sets the fill color drawn behind fenced code blocks and table cells.
    func markdownCodeBlockBackground(_ color: Color) -> some View {
        environment(\.markdownCodeBlockBackground, color)
    }

    /// Sets the Highlightr themes used for syntax highlighting.
    ///
    /// The theme matching the current appearance is applied; the renderer
    /// swaps automatically on dark/light changes. Theme names match Highlightr's
    /// bundled stylesheets — see the catalog at
    /// https://github.com/highlightjs/highlight.js/tree/main/src/styles
    /// (examples: `xcode`, `github`, `monokai`, `solarized-light`, `solarized-dark`,
    /// `dracula`, `nord`).
    func markdownCodeTheme(light: String, dark: String) -> some View {
        environment(\.markdownCodeTheme, MarkdownCodeTheme(light: light, dark: dark))
    }
}
