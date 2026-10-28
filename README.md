# SwiftMarkdownView

A fast, native SwiftUI view for rendering Markdown on macOS and iOS, built on TextKit with syntax-highlighted code blocks, tables, blockquotes, lists, and headings.

## Features

- Native rendering via `NSTextView` / `UITextView` (no `WKWebView`, no HTML).
- Syntax highlighting for ~50 languages, themed light/dark via [Highlightr](https://github.com/raspu/Highlightr).
- Tables (`NSTextTable` on macOS; tab-stop layout with row shading on iOS), with proportional column widths and inline-markdown cells.
- Blockquotes with depth bars, thematic breaks, ordered/unordered nested lists, headings (H1–H6), inline code, bold, italic.
- Per-code-block copy button (hover on macOS, always visible on iOS).
- Automatic streaming optimization: incremental updates coalesce to a debounced full render while showing live plaintext fragments, preserving text selection across updates.
- LRU render cache.
- Theme-aware: swaps Highlightr theme on light/dark transitions.
- Configurable font size, code-block background, and Highlightr themes via SwiftUI view modifiers.

## Requirements

- iOS 26+ / macOS 26+
- Swift 6.2+
- Xcode 26+

## Installation

Add the package via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/SilverMarcs/SwiftMarkdownView", from: "1.0.0")
]
```

Then add `"SwiftMarkdownView"` to your target's dependencies.

## Usage

```swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    let markdown: String

    var body: some View {
        SwiftMarkdownView(markdown) { height in
            // optional: receive the measured content height
        }
        .markdownFontSize(17)
        .markdownCodeBlockBackground(Color(.quaternarySystemFill))
        .markdownCodeTheme(light: "atom-one-light", dark: "atom-one-dark")
    }
}
```

## Modifiers

| Modifier | Description |
|---|---|
| `.markdownFontSize(_ size: CGFloat)` | Body font size. Code font derives from this (one point smaller, monospaced). |
| `.markdownCodeBlockBackground(_ color: Color)` | Fill drawn behind fenced code blocks and table cells. |
| `.markdownCodeTheme(light: String, dark: String)` | Highlightr theme names. Resolves against the current appearance and swaps automatically on dark/light transitions. Browse names at the [highlight.js styles directory](https://github.com/highlightjs/highlight.js/tree/main/src/styles). |

The constructor's optional `onHeightChange` closure receives the measured rendered height, useful for sizing a parent container around the view.

## Links on macOS

Markdown links use SwiftUI's environment `openURL` action. By default, macOS opens
the destination with the system handler. Override the action on the view or an
ancestor to handle links in your app:

```swift
SwiftMarkdownView("[Read more](https://example.com)")
    .environment(\.openURL, OpenURLAction { url in
        // Handle selected destinations here and return .handled.
        return .systemAction
    })
```

## Streaming

Streaming optimizations (debounced render + plaintext-fragment append) are automatic. When you pass updated content that prefix-extends the previous text (e.g. an LLM appending tokens), the renderer coalesces full re-renders to 180 ms intervals and shows incoming characters immediately as styled plaintext in between. Any non-appending update renders immediately. No explicit flag is needed.

## Limitations

- Custom SwiftUI `openURL` handling is currently supported on macOS only.
- No image rendering (`![alt](src)` is ignored).
- No math / LaTeX.
- No footnotes or task lists.
- iOS table rendering uses a tab-stop fallback (no cell borders, since `NSTextTable` isn't rendered by TextKit on UIKit). Headers and alternate rows are still shaded.

## License

MIT. See [LICENSE](LICENSE).
