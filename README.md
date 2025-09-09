# SwiftMarkdownView

`SwiftMarkdownView` is a surprisingly performant SwiftUI view that renders Markdown content.

I call it surprising because the underlying view is a `WKWebView`,

## Requirement for macOS Apps

The underlying web view loads an HTML string. For the package to work in a macOS app, enable the "Outgoing Connections (Client)" capability.

<details>
<summary>What it looks like in Xcode</summary>

![Outgoing Connections (Client)](https://user-images.githubusercontent.com/5054148/231693500-093f4185-658b-4fa2-a182-fb40f50147b7.png)

</details>

https://user-images.githubusercontent.com/5054148/231708816-6c992197-893d-4d94-ae7c-2c6ce8d8c427.mp4

## Features

<details>
<summary>Auto-adjusting View Height</summary>

The view's height is always the content's height.

<img alt="Auto-adjusting View Height" src="https://user-images.githubusercontent.com/5054148/231703096-42a34f79-ffda-49b6-b352-304baa98fe84.png" width="1000">

</details>

<details>
<summary>Text Selection</summary>

<img alt="Text Selection" src="https://user-images.githubusercontent.com/5054148/231701074-17333cc7-5774-46ed-800a-dd113ca8dd5d.png" width="1000">

</details>

<details>
<summary>Dynamic Content</summary>

https://user-images.githubusercontent.com/5054148/231708816-6c992197-893d-4d94-ae7c-2c6ce8d8c427.mp4

</details>

<details>
<summary>Code Block Themes</summary>
Multiple predefined themes are available for syntax highlighting, including GitHub, Atom, Tokyo Night, and more.
</details>

<details>
<summary>Text Highlighting</summary>
Highlight specific text within the markdown content for search or emphasis.
</details>

<details>
<summary>Font Size Customization</summary>
Easily adjust the font size of the rendered content.
</details>

## Supported Platforms

- macOS 11 and later
- iOS 14 and later

## Installation

Add this package as a dependency.

See the article [“Adding package dependencies to your app”](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) to learn more.

## Usage

### Display Markdown Content

```swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    @State private var markdownContent = "# Hello World"

    var body: some View {
        NavigationStack {
            SwiftMarkdownView(markdownContent)
        }
    }
}
```

### Customize Font Size

```swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    @State private var markdownContent = "# Hello World"

    var body: some View {
        NavigationStack {
            SwiftMarkdownView(
                markdownContent,
                fontSize: 18
            )
        }
    }
}
```

### Use Different Code Block Themes

````swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    @State private var markdownContent = """
    # Code Example
    ```swift
    print("Hello, World!")
    ```
    """

    var body: some View {
        NavigationStack {
            SwiftMarkdownView(
                markdownContent,
                codeBlockTheme: .tokyo
            )
        }
    }
}
````

Available themes: `.github` (default), `.atom`, `.a11y`, `.panda`, `.paraiso`, `.stackoverflow`, `.tokyo`

### Highlight Text

```swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    @State private var markdownContent = "# Hello World\nThis is some sample text."
    @State private var searchText = "sample"

    var body: some View {
        NavigationStack {
            SwiftMarkdownView(
                markdownContent,
                highlightString: searchText
            )
        }
    }
}
```

### Get Calculated Height

```swift
import SwiftUI
import SwiftMarkdownView

struct ContentView: View {
    @State private var markdownContent = "# Hello World"
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            SwiftMarkdownView(
                markdownContent,
                calculatedHeight: $contentHeight
            )

            Text("Content height: \(contentHeight)")
        }
    }
}
```

### All Parameters

```swift
SwiftMarkdownView(
    markdownContent,                    // The markdown string to render
    calculatedHeight: $height,          // Binding to get the calculated content height
    fontSize: 16,                       // Font size (default: 16)
    highlightString: "search term",     // Text to highlight (default: "")
    baseURL: "https://example.com",     // Base URL for relative links (default: "")
    codeBlockTheme: .github            // Code syntax theme (default: .github)
)
```

## Link Handling

Links are automatically opened in the default browser. Currently, custom link handling is not supported but may be added in future versions.

The underlying web view loads an HTML string. For the package to work in a macOS app, enable the “Outgoing Connections (Client)” capability.

<details>
<summary>What it looks like in Xcode</summary>

![Outgoing Connections (Client)](https://user-images.githubusercontent.com/5054148/231693500-093f4185-658b-4fa2-a182-fb40f50147b7.png)

</details>

## Requirement for macOS Apps

## Acknowledgements

Portions of this package may utilize the following copyrighted material, the use of which is hereby acknowledged.

- [markdown-it](https://github.com/markdown-it/markdown-it)\
   © 2014 Vitaly Puzrin, Alex Kocharin
- [Punycode.js](https://github.com/mathiasbynens/punycode.js)\
   © Mathias Bynens
- [highlight.js](https://github.com/highlightjs/highlight.js)\
   © 2006 Ivan Sagalaev
- [markdown-it-mark](https://github.com/markdown-it/markdown-it-mark)\
   © 2014-2015 Vitaly Puzrin, Alex Kocharin
- [markdown-it-task-lists](https://github.com/revin/markdown-it-task-lists)\
   © 2016, Revin Guillen
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)\
   © Sindre Sorhus
