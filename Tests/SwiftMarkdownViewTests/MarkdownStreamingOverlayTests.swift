#if !os(macOS)
import SwiftUI
import Testing
import UIKit
@testable import SwiftMarkdownView

/// A streaming reply re-renders as it grows; the tables and code blocks
/// overlaid on it must keep where the reader scrolled them.
@MainActor
struct MarkdownStreamingOverlayTests {
    private let table = """
    Intro paragraph.

    | Name | Role | Notes | More notes | Even more notes |
    | --- | --- | --- | --- | --- |
    | Ada Lovelace | Engineer | Wrote the first program for the analytical engine | Lots of text here | And here too |
    | Grace Hopper | Admiral | Built the first compiler and popularised debugging | More text | And more |
    """

    private let code = """
    ```swift
    let aVeryLongLineOfCodeThatScrollsSideways = compute(first: 1, second: 2, third: 3, fourth: 4, fifth: 5)
    ```
    """

    private func show(_ markdown: String, in view: MarkdownContainerView) async {
        let request = MarkdownRenderRequest(text: markdown, fontSize: 15, themeName: "xcode", codeBlockBackground: .gray)
        let document = await MarkdownRenderer(fontSize: 15, themeName: "xcode").render(markdown)
        view.apply(document: document, for: request)
        view.layoutIfNeeded()
    }

    private func makeView() -> MarkdownContainerView {
        let view = MarkdownContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }

    private func overlay<T: UIView>(_ type: T.Type, in view: MarkdownContainerView) -> T? {
        view.subviews.compactMap { $0 as? T }.first
    }

    private func columnViews(in tableView: MarkdownTableView) -> [UITextView] {
        tableView.subviews.flatMap(\.subviews).compactMap { $0 as? UITextView }
    }

    @Test func tableKeepsItsScrollWhenTextIsAppendedAfterIt() async throws {
        let view = makeView()
        await show(table, in: view)
        let tableView = try #require(overlay(MarkdownTableView.self, in: view))
        #expect(tableView.contentSize.width > tableView.bounds.width)
        let columns = columnViews(in: tableView)
        tableView.contentOffset.x = 60

        await show(table + "\n\nA paragraph streams in after the table.", in: view)

        #expect(overlay(MarkdownTableView.self, in: view) === tableView)
        #expect(tableView.contentOffset.x == 60)
        // A finished table isn't rebuilt.
        #expect(!columns.isEmpty)
        #expect(columnViews(in: tableView).elementsEqual(columns, by: ===))
    }

    @Test func tableKeepsItsScrollWhileItsRowsStream() async throws {
        let view = makeView()
        await show(table, in: view)
        let tableView = try #require(overlay(MarkdownTableView.self, in: view))
        tableView.contentOffset.x = 60

        await show(table + "\n| Katherine Johnson | Mathematician | Orbital mechanics | Text | Text |", in: view)

        #expect(overlay(MarkdownTableView.self, in: view) === tableView)
        #expect(tableView.contentOffset.x == 60)
        #expect(tableView.contentSize.height == tableView.bounds.height)
    }

    @Test func codeBlockKeepsItsScrollWhenTextIsAppendedAfterIt() async throws {
        let view = makeView()
        await show(code, in: view)
        let codeView = try #require(overlay(MarkdownCodeBlockView.self, in: view))
        #expect(codeView.contentSize.width > codeView.bounds.width)
        codeView.contentOffset.x = 40

        await show(code + "\n\nA paragraph streams in after the code.", in: view)

        #expect(overlay(MarkdownCodeBlockView.self, in: view) === codeView)
        #expect(codeView.contentOffset.x == 40)
    }
    @Test func codeBlockKeepsItsScrollWhileItsLinesStream() async throws {
        let view = makeView()
        let open = String(code.dropLast(3))
        await show(open, in: view)
        let codeView = try #require(overlay(MarkdownCodeBlockView.self, in: view))
        codeView.contentOffset.x = 40

        await show(open + "print(aVeryLongLineOfCodeThatScrollsSideways)\n", in: view)

        #expect(overlay(MarkdownCodeBlockView.self, in: view) === codeView)
        #expect(codeView.contentOffset.x == 40)
        #expect(codeView.contentSize.height == codeView.bounds.height)
    }

    /// An image above the streaming text that loads after the text moved on
    /// still takes its real size.
    @Test func earlierImageTakesItsSizeWhenItLoadsMidStream() async throws {
        let tallImage = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 200)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 200))
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        let view = makeView()
        window.addSubview(view)
        view.imageLoader = MarkdownImageLoading(id: UUID().uuidString) { _ in
            try? await Task.sleep(for: .milliseconds(300))
            return tallImage
        }
        let markdown = "Intro.\n\n![tall](test://tall.png)\n\n# Heading\n\nA paragraph after the image."
        await show(markdown, in: view)
        // The reply streams on while the image loads.
        await show(markdown + "\n\nText streams in after the image.", in: view)
        let imageView = try #require(overlay(MarkdownImageView.self, in: view))
        let placeholderHeight = imageView.frame.height

        for _ in 0..<50 where imageView.frame.height == placeholderHeight {
            try await Task.sleep(for: .milliseconds(50))
            view.layoutIfNeeded()
        }
        #expect(imageView.frame.height > placeholderHeight)
        #expect(imageView.frame.height > imageView.frame.width)
    }
}
#endif
