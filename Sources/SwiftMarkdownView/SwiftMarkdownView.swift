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
    @Entry var markdownImageLoader: MarkdownImageLoading = .default
    @Entry var markdownImageTapAction: MarkdownEnvironmentAction<@MainActor (MarkdownImageTap) -> Void>? = nil
    @Entry var markdownSelectionActions: [MarkdownSelectionAction] = []
    #if os(macOS)
    @Entry var showsMarkdownSelectionPopover = false
    #endif
}

/// An action offered beside Copy for selected text. Actions that show the
/// same compare equal, so setting a new closure on every update of an
/// ancestor doesn't update every Markdown view below. Views pick up a new
/// closure the next time they update.
struct MarkdownSelectionAction: Equatable {
    let title: String
    let systemImage: String
    let perform: @MainActor (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.systemImage == rhs.systemImage
    }
}

/// A closure in the environment that compares equal to any other, so setting
/// it again on every update of an ancestor doesn't update every Markdown view
/// below. Views pick up a new closure the next time they update.
struct MarkdownEnvironmentAction<Action>: Equatable {
    let action: Action

    init(_ action: Action) {
        self.action = action
    }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
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

    /// Loads the bytes of an image a Markdown document embeds, given its source as written
    /// (e.g. "/tmp/shot.png" or "https://…"). Return nil to show its alt text instead.
    ///
    /// A line made only of an image shows it as a block, fitted to the
    /// width, even right after a line of text; images written back to back show as a grid of thumbnails. Decoded images are cached in memory by `id` and source, so the
    /// loader runs once per image rather than on every render. Give each
    /// place sources resolve against its own `id` (e.g. one per host or
    /// conversation), since the same path there can mean a different file.
    /// Loaders with the same `id` are treated as interchangeable: a new
    /// closure with an unchanged `id` doesn't reload anything.
    ///
    /// Without a loader, http, https and data URLs are fetched with
    /// `URLSession` and other sources show their alt text.
    func markdownImageLoader(
        id: some Hashable & Sendable,
        _ loader: @escaping @Sendable (String) async -> Data?
    ) -> some View {
        environment(\.markdownImageLoader, MarkdownImageLoading(id: id, load: loader))
    }

    /// Called when someone taps or clicks an embedded image, with it and the
    /// images shown alongside it: a gallery's images, which are written back
    /// to back and shown as thumbnails, or only the one image.
    func onMarkdownImageTap(_ action: @escaping @MainActor (MarkdownImageTap) -> Void) -> some View {
        environment(\.markdownImageTapAction, MarkdownEnvironmentAction(action))
    }

    #if os(macOS)
    /// Shows Copy and configured selection actions in a popover after selecting text.
    func markdownSelectionPopover() -> some View {
        environment(\.showsMarkdownSelectionPopover, true)
    }
    #endif

    /// Offers an action beside Copy in the selection menu on iOS and in the
    /// context menu and optional selection popover on macOS. It's called with the
    /// selection as Copy would put it on the pasteboard as plain text, and
    /// the selection is cleared. While `isEnabled` is false, it isn't offered.
    ///
    /// Apply it more than once to offer several actions; they're listed in
    /// the order the modifiers are written. A disabled one leaves out only
    /// itself, not the actions applied around it.
    func markdownSelectionAction(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        perform: @escaping @MainActor (String) -> Void
    ) -> some View {
        // Outer modifiers run first, so each one goes ahead of those above it.
        transformEnvironment(\.markdownSelectionActions) { actions in
            guard isEnabled else { return }
            actions.insert(MarkdownSelectionAction(title: title, systemImage: systemImage, perform: perform), at: 0)
        }
    }
}
