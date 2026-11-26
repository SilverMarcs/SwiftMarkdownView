import Foundation
import Testing
@testable import SwiftMarkdownView

struct MarkdownNumberedListTests {
    @Test
    func numberedItemsAfterAParagraphStartAList() {
        #expect(MarkdownBlockSplitter.separatingNumberedLists([
            "**Open items:**",
            "4. **First.** Text.",
            "5. **Second.** Text."
        ]) == [
            "**Open items:**",
            "",
            "4. **First.** Text.",
            "5. **Second.** Text."
        ])
    }

    @Test
    func linesInsideAListAreLeftAlone() {
        let lines = [
            "1. **One.**",
            "   - nested",
            "lazy continuation",
            "2. **Two.**",
            "",
            "Paragraph.",
            "1. Starts at one, which CommonMark already allows."
        ]
        #expect(MarkdownBlockSplitter.separatingNumberedLists(lines) == lines)
    }

    @Test
    func yearsAndIndentedLinesStayText() {
        let lines = ["The year was", "1999. Great times.", "Indented", "   4. item"]
        #expect(MarkdownBlockSplitter.separatingNumberedLists(lines) == lines)
    }

    @Test
    func renderedRunOnSectionBecomesAList() async {
        let markdown = "**Open items:**\n4. **First.** Text.\n5. **Second.** Text."
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)
        let lines = document.attributedString.string.components(separatedBy: .newlines)
        #expect(lines.first == "Open items:")
        #expect(lines.contains { $0.hasPrefix("5.") && $0.hasSuffix("Second. Text.") })
    }
}
