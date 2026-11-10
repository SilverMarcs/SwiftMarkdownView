#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import SwiftMarkdownView

@MainActor
struct MarkdownPreparedTextTests {
    private let markdown = """
    # Heading

    Some **bold** text, `code` and a [link](https://example.com) in a paragraph long enough to wrap onto more than one line at this width.

    - One
    - Two
      - Nested

    ```swift
    let value = compute(1, 2)
    print(value)
    ```

    | Name | Role | Notes |
    | --- | --- | --- |
    | Ada | Engineer | Wrote the first program |
    | Grace | Admiral | Compilers |

    > A quote to finish.
    """

    @Test(arguments: [320.0, 640.0])
    func preparedLayoutMatchesTheViewsOwnLayout(width: CGFloat) async {
        let request = MarkdownRenderRequest(text: markdown, fontSize: 13, themeName: "xcode", codeBlockBackground: .gray)
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)
        let prepared = await Task.detached {
            MarkdownPreparedText(request: request, document: document, width: width)
        }.value

        let measured = MarkdownContainerView()
        measured.apply(document: document, for: request)
        let expected = measured.measuredSize(for: width)

        let adopting = MarkdownContainerView(prepared: prepared)
        #expect(prepared.size == expected)
        #expect(adopting.isShowing(request))
        #expect(adopting.measuredSize(for: width) == expected)
    }
}
#endif
