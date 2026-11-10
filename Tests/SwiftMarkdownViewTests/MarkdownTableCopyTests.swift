#if os(macOS)
import AppKit
import Testing
@testable import SwiftMarkdownView

@MainActor
struct MarkdownTableCopyTests {
    private let markdown = """
    Intro

    | Name | Role |
    | --- | --- |
    | Ada | Engineer |
    | Grace | Admiral |

    Outro
    """

    @Test
    func selectionInsideOneCellCopiesOnlyThatText() async throws {
        let (storage, document) = await rendered()
        let payload = try copy(storage, document, from: "Engin", to: "eer")
        #expect(payload.plainText == "Engineer")
        #expect(payload.html == "Engineer")
    }

    @Test
    func selectionAcrossCellsCopiesTheSelectedCells() async throws {
        let (storage, document) = await rendered()
        let payload = try copy(storage, document, from: "da", to: "Grace")
        #expect(payload.plainText == "da\tEngineer\nGrace")
        #expect(payload.html == "<table><tr><td>da</td><td>Engineer</td></tr><tr><td>Grace</td></tr></table>")
    }

    @Test
    func selectionFromAboveIntoTableKeepsTheSurroundingText() async throws {
        let (storage, document) = await rendered()
        let payload = try copy(storage, document, from: "Intro", to: "Role")
        #expect(payload.plainText == "Intro\n\nName\tRole")
    }

    @Test
    func selectingTheWholeTableCopiesItAllAsATable() async throws {
        let (storage, document) = await rendered()
        let payload = try copy(storage, document, from: "Name", to: "Admiral")
        #expect(payload.plainText == "Name\tRole\nAda\tEngineer\nGrace\tAdmiral")
        #expect(payload.html.hasPrefix("<table><thead>"))
    }

    private func rendered() async -> (NSTextStorage, MarkdownRenderedDocument) {
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)
        return (NSTextStorage(attributedString: document.attributedString), document)
    }

    private func copy(
        _ storage: NSTextStorage,
        _ document: MarkdownRenderedDocument,
        from start: String,
        to end: String
    ) throws -> MarkdownCopyPayload {
        let string = storage.string as NSString
        let startRange = string.range(of: start)
        let endRange = string.range(of: end, options: .backwards)
        try #require(startRange.location != NSNotFound && endRange.location != NSNotFound)
        let selection = NSRange(location: startRange.location, length: NSMaxRange(endRange) - startRange.location)
        return try #require(MarkdownCopyPayload.build(from: storage, tableBlocks: document.tableBlocks, selection: selection))
    }
}
#endif
