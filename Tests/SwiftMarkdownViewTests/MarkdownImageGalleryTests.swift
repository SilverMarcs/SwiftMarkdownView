import Foundation
import Testing
@testable import SwiftMarkdownView

struct MarkdownImageGalleryTests {
    private static func image(_ name: String) -> MarkdownImage {
        MarkdownImage(source: "/tmp/\(name).png", altText: name)
    }

    @Test
    func imageParagraphsWithOnlyBlankLinesBetweenAreOneGallery() {
        let lines = [
            "Screenshots:",
            "",
            "![a](/tmp/a.png)",
            "",
            "![b](/tmp/b.png)",
            "![c](/tmp/c.png)",
            "",
            "Then text.",
            "",
            "![d](/tmp/d.png)"
        ]
        #expect(MarkdownImageSyntax.split(lines) == [
            .markdown(["Screenshots:", ""]),
            .images([Self.image("a"), Self.image("b"), Self.image("c")]),
            .markdown(["", "Then text.", ""]),
            .images([Self.image("d")])
        ])
    }

    @Test
    func galleryImagesShareOneLineAndKnowTheirPlace() async {
        let markdown = "![a](/tmp/a.png)\n\n![b](/tmp/b.png)\n\n![c](/tmp/c.png)\n\n---\n\n![d](/tmp/d.png)"
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)

        #expect(document.imageBlocks.map(\.gallery) == [
            MarkdownImageGalleryPosition(index: 0, count: 3),
            MarkdownImageGalleryPosition(index: 1, count: 3),
            MarkdownImageGalleryPosition(index: 2, count: 3),
            nil
        ])
        let string = document.attributedString.string as NSString
        let galleryEnd = NSMaxRange(document.imageBlocks[2].range)
        let galleryText = string.substring(to: galleryEnd)
        #expect(!galleryText.contains("\n"))
    }

    @Test
    func galleriesFitTheirColumnsUpToAMaximumSide() {
        let spacing = MarkdownImageMetrics.gallerySpacing
        let side = MarkdownImageMetrics.galleryMaxThumbnailSide
        #expect(MarkdownImageMetrics.gallerySize(count: 3, availableWidth: 1000)
            == CGSize(width: side * 3 + spacing * 2, height: side))
        #expect(MarkdownImageMetrics.gallerySize(count: 4, availableWidth: 1000)
            == CGSize(width: side * 2 + spacing, height: side * 2 + spacing))
        // Narrow: three columns share the width.
        #expect(MarkdownImageMetrics.gallerySize(count: 5, availableWidth: 308)
            == CGSize(width: 100 * 3 + spacing * 2, height: 100 * 2 + spacing))
    }
}

#if os(macOS)
import AppKit

@MainActor
struct MarkdownImageGalleryLayoutTests {
    @Test
    func galleryThumbnailsLayOutInAGrid() async throws {
        let markdown = "Shots:\n\n![a](/tmp/a.png)\n![b](/tmp/b.png)\n![c](/tmp/c.png)\n![d](/tmp/d.png)\n\nAfter."
        let width: CGFloat = 308
        let request = MarkdownRenderRequest(text: markdown, fontSize: 13, themeName: "xcode", codeBlockBackground: .gray)
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)
        // Nothing loaded: a gallery's layout doesn't wait for its images.
        let images = MarkdownPreparedImages(loaderID: AnyHashable("gallery-test"), states: [:], displayScale: 2)
        let prepared = await Task.detached {
            MarkdownPreparedText(request: request, document: document, width: width, images: images)
        }.value

        let frames = prepared.layoutManager.imageBlockFrames(in: prepared.container).map(\.frame)
        try #require(frames.count == 4)
        let side: CGFloat = 152
        let spacing = MarkdownImageMetrics.gallerySpacing
        #expect(frames.allSatisfy { $0.size == CGSize(width: side, height: side) })
        #expect(frames[1].minX == frames[0].maxX + spacing)
        #expect(frames[1].minY == frames[0].minY)
        #expect(frames[2].minX == frames[0].minX)
        #expect(frames[2].minY == frames[0].maxY + spacing)
        #expect(frames[3].origin == CGPoint(x: frames[1].minX, y: frames[2].minY))
        // The text after the gallery sits below it.
        #expect(prepared.size.height > frames[3].maxY)

        let measured = MarkdownContainerView()
        measured.apply(document: document, for: request)
        #expect(measured.measuredSize(for: width) == prepared.size)
    }
}
#endif
