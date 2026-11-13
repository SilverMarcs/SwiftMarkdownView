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

    @Test
    func preparedImagesLayOutAtTheirLoadedSize() async throws {
        let markdown = "A screenshot:\n\n![Shot](shot.png)\n\nAnd some text after it."
        let png = try #require(Self.png(width: 900, height: 300))
        let loader = MarkdownImageLoading(id: "prepared-images-test") { _ in png }
        let store = MarkdownImageStore.shared
        let key = MarkdownImageKey(loaderID: loader.id, source: "shot.png")
        let owner = NSObject()
        await withCheckedContinuation { continuation in
            store.load(key, using: loader.load, for: owner) { continuation.resume() }
        }
        #expect(store.layoutState(for: key) == .loaded(pixelSize: CGSize(width: 900, height: 300)))

        let width: CGFloat = 640
        let request = MarkdownRenderRequest(text: markdown, fontSize: 13, themeName: "xcode", codeBlockBackground: .gray)
        let document = await MarkdownRenderer(fontSize: 13, themeName: "xcode").render(markdown)
        let block = try #require(document.imageBlocks.first)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let images = MarkdownPreparedImages(loaderID: loader.id, states: [block.id: store.layoutState(for: key)], displayScale: scale)
        let prepared = await Task.detached {
            MarkdownPreparedText(request: request, document: document, width: width, images: images)
        }.value

        let measured = MarkdownContainerView()
        measured.imageLoader = loader
        measured.apply(document: document, for: request)
        let expected = measured.measuredSize(for: width)
        // The image is part of the layout.
        #expect(expected.height > 300 / scale)

        let adopting = MarkdownContainerView(prepared: prepared)
        adopting.imageLoader = loader
        #expect(prepared.size == expected)
        #expect(adopting.isLaidOut(atWidth: width))
        #expect(adopting.measuredSize(for: width) == expected)
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
#endif
