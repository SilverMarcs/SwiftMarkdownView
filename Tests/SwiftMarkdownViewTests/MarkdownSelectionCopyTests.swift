#if os(iOS)
import Testing
import UIKit
@testable import SwiftMarkdownView

@MainActor
struct MarkdownSelectionCopyTests {
    nonisolated private static let samples = [
        "Plain **bold** *em* `code` [link](https://example.com) text.",
        "# Heading\n\n- one\n- two\n  1. nested\n\n> quoted\n\n---\n\nAfter",
        "Before\n\n```swift\nlet x = 1\n```\n\nAfter",
        "Intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nOutro",
        "Text ![alt](https://example.com/a.png) more",
        "Code\n\n```\nlet x = 1\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n![alt](https://example.com/a.png)",
    ]

    @Test(arguments: samples)
    func copyingTheWholeReplyDoesNotCrash(_ markdown: String) async {
        let view = await textView(showing: markdown)
        view.selectedRange = NSRange(location: 0, length: view.markdownTextStorage.length)
        view.copy(nil)
    }

    @Test
    func copyingACodeBlockCopiesItsSource() async throws {
        let view = await textView(showing: "Before\n\n```swift\nlet x = 1\n```\n\nAfter")
        let payload = try #require(MarkdownCopyPayload.build(
            from: view.markdownTextStorage,
            tableBlocks: view.markdownLayoutManager.tableBlocks,
            codeBlocks: view.markdownLayoutManager.codeBlocks,
            imageBlocks: view.markdownLayoutManager.imageBlocks,
            selection: NSRange(location: 0, length: view.markdownTextStorage.length)
        ))
        #expect(payload.plainText.contains("let x = 1"))
        #expect(payload.html.contains("<pre><code>let x = 1"))
    }

    private func textView(showing markdown: String) async -> MarkdownPlainTextView {
        let document = await MarkdownRenderer(fontSize: 17, themeName: "xcode").render(markdown)
        let view = MarkdownPlainTextView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        view.update(document: document)
        return view
    }
}
#endif
