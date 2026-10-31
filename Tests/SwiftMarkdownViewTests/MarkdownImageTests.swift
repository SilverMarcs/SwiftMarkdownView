import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SwiftMarkdownView

@Suite("Image syntax")
struct MarkdownImageSyntaxTests {
    @Test func parsesPlainDestination() throws {
        let images = try #require(MarkdownImageSyntax.images(inLine: "![A shot](/tmp/shot.png)"))
        #expect(images == [MarkdownImage(source: "/tmp/shot.png", altText: "A shot")])
    }

    @Test func parsesAngleBracketDestinationWithSpacesAndEscapes() throws {
        let images = try #require(MarkdownImageSyntax.images(inLine: #"![x](</path/with space/a\<b\>.png>)"#))
        #expect(images.first?.source == "/path/with space/a<b>.png")
    }

    @Test(arguments: [
        #"![x](/a.png "The title")"#,
        #"![x](/a.png 'The title')"#,
        #"![x](/a.png (The title))"#,
        #"![x](</a.png> "The title")"#,
    ])
    func parsesTitles(line: String) throws {
        let image = try #require(MarkdownImageSyntax.images(inLine: line)?.first)
        #expect(image.source == "/a.png")
        #expect(image.title == "The title")
    }

    @Test func parsesHTTPURLs() throws {
        let image = try #require(MarkdownImageSyntax.images(inLine: "![logo](https://example.com/a/logo.png?size=2)")?.first)
        #expect(image.source == "https://example.com/a/logo.png?size=2")
    }

    @Test func parsesSeveralImagesOnOneLine() throws {
        let images = try #require(MarkdownImageSyntax.images(inLine: "  ![a](/a.png)  ![b](/b.png)\t![](/c.png) "))
        #expect(images.map(\.source) == ["/a.png", "/b.png", "/c.png"])
        #expect(images.map(\.altText) == ["a", "b", ""])
    }

    @Test func keepsBalancedParenthesesAndEscapedAltText() throws {
        let image = try #require(MarkdownImageSyntax.images(inLine: #"![a \[b\] [c]](/x/(1).png)"#)?.first)
        #expect(image.source == "/x/(1).png")
        #expect(image.altText == "a [b] [c]")
    }

    @Test(arguments: [
        "Here: ![a](/a.png)",
        "![a](/a.png) and some text",
        "[a](/a.png)",
        "![a]()",
        "![a](/a b.png)",
        "![a](/a.png",
        "![a][ref]",
        "    ![a](/a.png)",
        "\t![a](/a.png)",
    ])
    func rejectsLinesThatAreNotOnlyImages(line: String) {
        #expect(MarkdownImageSyntax.images(inLine: line) == nil)
    }

    @Test func splitsImageParagraphsFromText() {
        let pieces = MarkdownImageSyntax.split([
            "Before",
            "",
            "![a](/a.png)",
            "![b](</b c.png>)",
            "",
            "After",
        ])
        #expect(pieces == [
            .markdown(["Before", ""]),
            .images([
                MarkdownImage(source: "/a.png", altText: "a"),
                MarkdownImage(source: "/b c.png", altText: "b"),
            ]),
            .markdown(["", "After"]),
        ])
    }

    @Test func keepsImagesThatContinueAParagraphInline() {
        let lines = ["Here's the shot:", "![a](/a.png)"]
        #expect(MarkdownImageSyntax.split(lines) == [.markdown(lines)])

        let trailing = ["![a](/a.png)", "with a caption on the next line"]
        #expect(MarkdownImageSyntax.split(trailing) == [.markdown(trailing)])
    }

    @Test func treatsImagesAfterAHeadingAsAParagraph() {
        let pieces = MarkdownImageSyntax.split(["## Result", "![a](/a.png)"])
        #expect(pieces == [.markdown(["## Result"]), .images([MarkdownImage(source: "/a.png", altText: "a")])])
    }

    @Test func ignoresImagesInTildeFences() {
        let lines = ["~~~", "", "![a](/a.png)", "", "~~~"]
        #expect(MarkdownImageSyntax.split(lines) == [.markdown(lines)])
    }

    @Test func labelsImagesByAltTextOrFileName() {
        #expect(MarkdownImage(source: "/tmp/shot.png", altText: "Shot").label == "Shot")
        #expect(MarkdownImage(source: "/tmp/my shot.png", altText: " ").label == "my shot.png")
        #expect(MarkdownImage(source: "https://example.com/a/b.jpg?x=1", altText: "").label == "b.jpg")
    }
}

@Suite("Image rendering")
struct MarkdownImageRenderingTests {
    private func render(_ markdown: String) async -> MarkdownRenderedDocument {
        await MarkdownRenderer(fontSize: 13, themeName: "atom-one-light").render(markdown)
    }

    @Test func rendersImageParagraphsAsBlocks() async throws {
        let document = await render("Intro\n\n![one](/a.png)\n![two](/b.png)\n\nOutro")
        #expect(document.imageBlocks.map(\.image.source) == ["/a.png", "/b.png"])
        #expect(document.imageBlocks.map(\.id) == [0, 1])

        let string = document.attributedString.string as NSString
        for block in document.imageBlocks {
            #expect(string.substring(with: block.range) == "\u{200B}")
            let id = document.attributedString.attribute(.markdownImageBlockID, at: block.range.location, effectiveRange: nil) as? Int
            #expect(id == block.id)
        }
        #expect(document.attributedString.string.hasPrefix("Intro"))
        #expect(document.attributedString.string.hasSuffix("Outro"))
        #expect(!document.attributedString.string.contains("one"))
    }

    @Test func keepsInlineImagesAsAltText() async {
        let document = await render("Look at ![the chart](/chart.png) here.")
        #expect(document.imageBlocks.isEmpty)
        #expect(document.attributedString.string.contains("the chart"))
    }

    @Test func leavesImagesInCodeBlocksAlone() async {
        let document = await render("```md\n![a](/a.png)\n```")
        #expect(document.imageBlocks.isEmpty)
        #expect(document.codeBlocks.count == 1)
    }

    @Test func numbersImagesAcrossSegments() async {
        let document = await render("![a](/a.png)\n\n```\ncode\n```\n\n![b](/b.png)")
        #expect(document.imageBlocks.map(\.id) == [0, 1])
        #expect(document.codeBlocks.count == 1)
    }

    @Test func copiesImagesAsMarkdown() async throws {
        let document = await render("Intro\n\n![my shot](</tmp/my shot.png>)")
        let storage = NSTextStorage(attributedString: document.attributedString)
        let payload = try #require(MarkdownCopyPayload.build(
            from: storage,
            tableBlocks: [],
            imageBlocks: document.imageBlocks,
            selection: storage.fullRange
        ))
        #expect(payload.plainText == "Intro\n\n![my shot](</tmp/my shot.png>)")
        #expect(payload.html.contains(#"<img src="/tmp/my shot.png" alt="my shot">"#))
    }
}

@Suite("Image metrics")
struct MarkdownImageMetricsTests {
    @Test func neverScalesImagesUp() {
        let size = MarkdownImageMetrics.fittedSize(natural: CGSize(width: 200, height: 100), availableWidth: 600)
        #expect(size == CGSize(width: 200, height: 100))
    }

    @Test func fitsWideImagesToTheWidth() {
        let size = MarkdownImageMetrics.fittedSize(natural: CGSize(width: 1200, height: 600), availableWidth: 600)
        #expect(size == CGSize(width: 600, height: 300))
    }

    @Test func capsTallImages() {
        let size = MarkdownImageMetrics.fittedSize(natural: CGSize(width: 400, height: 2080), availableWidth: 600)
        #expect(size == CGSize(width: 100, height: MarkdownImageMetrics.maxHeight))
    }

    @Test func sizesPlaceholdersAtSixteenByNine() {
        #expect(MarkdownImageMetrics.placeholderSize(availableWidth: 640) == CGSize(width: 640, height: 360))
        #expect(MarkdownImageMetrics.placeholderSize(availableWidth: 2000).height == MarkdownImageMetrics.maxHeight)
    }

    @Test func fitsFailureRowsToTheWidth() {
        let size = MarkdownImageMetrics.failureSize(label: String(repeating: "long ", count: 100), fontSize: 13, availableWidth: 300)
        #expect(size.width == 300)
        #expect(size.height > 13 && size.height < 40)
    }
}

@Suite("Image loading")
struct MarkdownImageLoadingTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func decodesImagesAtTheirFullSize() throws {
        let asset = try #require(MarkdownImageAsset.decode(try pngData(width: 40, height: 30), maxPixelSize: 2560))
        #expect(asset.pixelSize == CGSize(width: 40, height: 30))
        #expect(asset.cgImage.width == 40)
    }

    @Test func downsamplesLargeImagesButKeepsTheirSize() throws {
        let asset = try #require(MarkdownImageAsset.decode(try pngData(width: 400, height: 200), maxPixelSize: 100))
        #expect(asset.pixelSize == CGSize(width: 400, height: 200))
        #expect(asset.cgImage.width == 100)
        #expect(asset.cgImage.height == 50)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(MarkdownImageAsset.decode(Data("not an image".utf8), maxPixelSize: 100) == nil)
    }

    @Test func defaultLoaderReadsDataURLsAndSkipsFilePaths() async throws {
        let png = try pngData(width: 2, height: 2)
        let data = await MarkdownImageLoading.default.load("data:image/png;base64,\(png.base64EncodedString())")
        #expect(data == png)
        #expect(await MarkdownImageLoading.default.load("/tmp/shot.png") == nil)
    }

    @Test func scopesImagesByLoaderID() {
        let loader: @Sendable (String) async -> Data? = { _ in nil }
        #expect(MarkdownImageLoading(id: "host-a", load: loader) == MarkdownImageLoading(id: "host-a", load: loader))
        #expect(MarkdownImageLoading(id: "host-a", load: loader) != MarkdownImageLoading(id: "host-b", load: loader))
        #expect(MarkdownImageLoading(id: 1, load: loader) != MarkdownImageLoading(id: "1", load: loader))
        #expect(MarkdownImageKey(loaderID: "host-a", source: "/a.png") != MarkdownImageKey(loaderID: "host-b", source: "/a.png"))
    }

    @MainActor
    @Test func cachesImagesPerLoader() async throws {
        let png = try pngData(width: 8, height: 4)
        let store = MarkdownImageStore.shared
        let hostA = MarkdownImageKey(loaderID: "test-host-a", source: "/shot.png")
        let hostB = MarkdownImageKey(loaderID: "test-host-b", source: "/shot.png")
        let owner = NSObject()

        await withCheckedContinuation { continuation in
            store.load(hostA, using: { _ in png }, for: owner) { continuation.resume() }
        }
        #expect(store.asset(for: hostA) != nil)
        #expect(store.layoutState(for: hostA) == .loaded(pixelSize: CGSize(width: 8, height: 4)))
        #expect(store.asset(for: hostB) == nil)
        #expect(store.layoutState(for: hostB) == .pending)
        #expect(store.needsLoad(hostB))

        await withCheckedContinuation { continuation in
            store.load(hostB, using: { _ in nil }, for: owner) { continuation.resume() }
        }
        #expect(store.layoutState(for: hostB) == .failed)
        #expect(store.asset(for: hostA) != nil)
    }
}
