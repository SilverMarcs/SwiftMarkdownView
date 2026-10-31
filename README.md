# SwiftMarkdownView

A fast, native SwiftUI view for rendering Markdown on macOS and iOS, built on TextKit with syntax-highlighted code blocks, tables, images, blockquotes, lists, and headings.

## Features

- Native rendering via `NSTextView` / `UITextView` (no `WKWebView`, no HTML).
- Syntax highlighting for ~50 languages, themed light/dark via [Highlightr](https://github.com/raspu/Highlightr).
- Tables (`NSTextTable` on macOS; tab-stop layout with row shading on iOS), with proportional column widths and inline-markdown cells.
- Images: a paragraph made only of images shows them as rounded blocks, fitted to the width (never scaled past their natural size, very tall ones capped), loaded asynchronously through a pluggable loader with an in-memory cache. Tap/click handling, Copy Image in the context menu, and alt text for accessibility.
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
        .markdownImageLoader(id: hostID) { source in
            // Return the image's bytes, or nil to show its alt text.
            try? await imageData(at: source)
        }
        .onMarkdownImageTap { source in
            // Open or preview the image.
        }
    }
}
```

## Modifiers

| Modifier | Description |
|---|---|
| `.markdownFontSize(_ size: CGFloat)` | Body font size. Code font derives from this (one point smaller, monospaced). |
| `.markdownCodeBlockBackground(_ color: Color)` | Fill drawn behind fenced code blocks and table cells. |
| `.markdownCodeTheme(light: String, dark: String)` | Highlightr theme names. Resolves against the current appearance and swaps automatically on dark/light transitions. Browse names at the [highlight.js styles directory](https://github.com/highlightjs/highlight.js/tree/main/src/styles). |
| `.markdownImageLoader(id: some Hashable & Sendable, _ loader: @Sendable (String) async -> Data?)` | Loads an embedded image's bytes from its source as written (`/tmp/shot.png`, `https://…`). Return `nil` to show the alt text. Decoded images are cached by `id` and source. See [Images](#images). |
| `.onMarkdownImageTap(_ action: @MainActor (String) -> Void)` | Called with an image's source when it's tapped or clicked. |

The constructor's optional `onHeightChange` closure receives the measured rendered height, useful for sizing a parent container around the view.

## Images

A paragraph made only of images (one or more, separated by spaces or line
breaks) renders them as blocks, in order:

```markdown
Here's the result:

![Before](/tmp/before.png)
![After](</Users/me/Screen Shot.png> "Optional title")
```

Images inside a sentence keep showing their alt text. Destinations can be
plain, in angle brackets (for paths with spaces, with `\<` and `\>` escapes),
http(s), or data URLs, with an optional title.

Each image fits the available width without being scaled past its natural size
(pixels at the screen scale), is capped at 520 pt tall, and has rounded
corners. A placeholder holds its place while it loads, and if it can't load, a
compact row shows a photo symbol with the alt text (or the file name).

Images load after the text renders, through the loader you set with
`markdownImageLoader(id:_:)`. Without one, http, https and data URLs are fetched
with `URLSession` and any other source shows its alt text. Decoded images
(GIFs show their first frame) are kept in an in-memory cache keyed by the
loader's `id` and the source, shared by every Markdown view, so re-renders,
streaming updates and scrolling back don't reload them, and their sizes are
remembered so a reloaded image doesn't shift the layout. Give each place sources
resolve against its own `id`, such as one per host or conversation, since the
same path there can be a different file. A new loader closure with the same `id`
doesn't reload anything. Loads stop when a view leaves the window, and failed
images are retried when shown again after 30 seconds.

```swift
SwiftMarkdownView(message.text)
    .markdownImageLoader(id: message.hostID) { source in
        await host.fileData(atPath: source)
    }
    .onMarkdownImageTap { source in
        preview(source)
    }
```

Selecting across an image copies it as Markdown (`![alt](source)`); the image's
context menu has **Copy Image**.

## Links on macOS

Right-click a Markdown link to copy its destination with **Copy Link**. Any
context-menu items supplied by an ancestor view remain available.

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
- Images inside a sentence, in lists or in blockquotes show their alt text; only paragraphs made only of images render images. Reference-style images (`![alt][ref]`) aren't supported.
- Animated images show their first frame. SVG and PDF images aren't decoded.
- No math / LaTeX.
- No footnotes or task lists.
- iOS table rendering uses a tab-stop fallback (no cell borders, since `NSTextTable` isn't rendered by TextKit on UIKit). Headers and alternate rows are still shaded.

## License

MIT. See [LICENSE](LICENSE).
