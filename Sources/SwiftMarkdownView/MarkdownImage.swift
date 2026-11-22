import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An image a Markdown document embeds with `![alt](source "title")`.
public struct MarkdownImage: Hashable, Sendable {
    /// The destination as written, without angle brackets or backslash escapes,
    /// e.g. `/tmp/shot.png` or `https://example.com/a.png`.
    public let source: String
    public let altText: String
    public let title: String?

    public init(source: String, altText: String, title: String? = nil) {
        self.source = source
        self.altText = altText
        self.title = title
    }

    /// Text describing the image: its alt text, or the file name from its source.
    public var label: String {
        let alt = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard alt.isEmpty else { return alt }
        let url = URL(string: source)
        guard url?.scheme?.lowercased() != "data" else { return String(localized: "Image") }
        let path = url?.path(percentEncoded: false) ?? source
        let name = path.split(separator: "/").last.map(String.init) ?? source
        return name.isEmpty ? source : name
    }
}

/// An image shown as its own block, from a line made only of images.
/// Its range is a single invisible character on a line the layout manager
/// sizes to fit the image, where `MarkdownContainerView` overlays it.
///
/// Images written back to back form a gallery instead: their characters
/// share one line, sized to fit a grid of square thumbnails.
public struct MarkdownImageBlock: Sendable {
    public let id: Int
    public let range: NSRange
    public let image: MarkdownImage
    /// Where the image sits in its gallery, or nil when it's shown on its own.
    public let gallery: MarkdownImageGalleryPosition?

    public init(id: Int, range: NSRange, image: MarkdownImage, gallery: MarkdownImageGalleryPosition? = nil) {
        self.id = id
        self.range = range
        self.image = image
        self.gallery = gallery
    }
}

/// An image's place among images written back to back, which show together
/// as a grid of thumbnails. A gallery's blocks have consecutive IDs.
public struct MarkdownImageGalleryPosition: Hashable, Sendable {
    public let index: Int
    public let count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }
}

/// An image someone tapped or clicked, with the images shown alongside it:
/// its gallery's, or only itself.
public struct MarkdownImageTap: Sendable {
    public let images: [MarkdownImage]
    /// Where the tapped image is in `images`.
    public let index: Int

    public init(images: [MarkdownImage], index: Int) {
        self.images = images
        self.index = index
    }

    public var image: MarkdownImage { images[index] }
}

// MARK: - Syntax

/// Finds lines made only of images, which render as image blocks, whether
/// they start a paragraph or follow its text. Images inside a sentence are
/// left to Foundation, which shows their alt text.
enum MarkdownImageSyntax {
    enum Piece: Equatable {
        case markdown([String])
        case images([MarkdownImage])
    }

    /// Splits lines of Markdown, outside fenced code and tables, into runs of
    /// Markdown and paragraphs made only of images. Image paragraphs with
    /// only blank lines between them are one piece, shown as a gallery.
    static func split(_ lines: [String]) -> [Piece] {
        var pieces: [Piece] = []
        for piece in paragraphs(lines) {
            if case .images(let images) = piece {
                if case .images(let previous) = pieces.last {
                    pieces[pieces.count - 1] = .images(previous + images)
                    continue
                }
                if pieces.count >= 2, case .markdown(let between) = pieces[pieces.count - 1],
                   between.allSatisfy(isBlank), case .images(let previous) = pieces[pieces.count - 2] {
                    pieces.removeLast()
                    pieces[pieces.count - 1] = .images(previous + images)
                    continue
                }
            }
            pieces.append(piece)
        }
        return pieces
    }

    /// Runs of Markdown and paragraphs made only of images, as written.
    private static func paragraphs(_ lines: [String]) -> [Piece] {
        var pieces: [Piece] = []
        var markdownLines: [String] = []
        var fence: String?
        var index = 0

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            pieces.append(.markdown(markdownLines))
            markdownLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]

            if let openFence = fence {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(openFence) { fence = nil }
                markdownLines.append(line)
                index += 1
                continue
            }
            if let openedFence = fenceMarker(in: line) {
                fence = openedFence
                markdownLines.append(line)
                index += 1
                continue
            }

            // A paragraph starts after a blank line or a single-line block.
            let startsParagraph = index == 0 || isBlank(lines[index - 1])
                || isHeading(lines[index - 1]) || isThematicBreak(lines[index - 1])
            // A line of images right after text, as in a caption with its image
            // on the next line, shows as a block too. Indented, it continues
            // the list item above, so it stays in it.
            if startsParagraph || !line.hasPrefix(" "), var images = images(inLine: line) {
                var end = index + 1
                while end < lines.count, let more = self.images(inLine: lines[end]) {
                    images += more
                    end += 1
                }
                // Text on the next line shows below the images, unless it
                // underlines them as a heading.
                if end == lines.count || !isSetextUnderline(lines[end]) {
                    flushMarkdown()
                    pieces.append(.images(images))
                    index = end
                    continue
                }
            }

            markdownLines.append(line)
            index += 1
        }

        flushMarkdown()
        return pieces
    }

    /// The images on a line made only of images and whitespace, or nil.
    static func images(inLine line: String) -> [MarkdownImage]? {
        guard line.drop(while: { $0 == " " }).hasPrefix("![") else { return nil }
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " { index += 1 }
        // Four spaces or a tab start indented code.
        guard index < 4, index < characters.count, characters[index] != "\t" else { return nil }

        var images: [MarkdownImage] = []
        while true {
            while index < characters.count, characters[index].isMarkdownSpace { index += 1 }
            guard index < characters.count else { break }
            guard let image = image(in: characters, at: &index) else { return nil }
            images.append(image)
        }
        return images.isEmpty ? nil : images
    }

    /// Parses `![alt](destination "title")` starting at `index`.
    private static func image(in characters: [Character], at index: inout Int) -> MarkdownImage? {
        var i = index
        guard i + 1 < characters.count, characters[i] == "!", characters[i + 1] == "[" else { return nil }
        i += 2

        // Alt text: up to the matching bracket.
        let altStart = i
        var depth = 1
        while i < characters.count {
            switch characters[i] {
            case "\\": i += 1
            case "[": depth += 1
            case "]": depth -= 1
            default: break
            }
            if depth == 0 { break }
            i += 1
        }
        guard i < characters.count, depth == 0 else { return nil }
        let alt = unescaped(characters[altStart..<i])
        i += 1

        guard i < characters.count, characters[i] == "(" else { return nil }
        i += 1
        skipSpaces(characters, &i)

        guard let source = destination(in: characters, at: &i), !source.isEmpty else { return nil }

        var title: String?
        let beforeTitle = i
        skipSpaces(characters, &i)
        if i > beforeTitle, i < characters.count, let closer = titleCloser(for: characters[i]) {
            i += 1
            let titleStart = i
            while i < characters.count, characters[i] != closer {
                if characters[i] == "\\" { i += 1 }
                i += 1
            }
            guard i < characters.count else { return nil }
            title = unescaped(characters[titleStart..<i])
            i += 1
            skipSpaces(characters, &i)
        }

        guard i < characters.count, characters[i] == ")" else { return nil }
        index = i + 1
        return MarkdownImage(source: source, altText: alt, title: title)
    }

    /// A link destination: `<…>` with escapes, or text without spaces whose
    /// parentheses balance.
    private static func destination(in characters: [Character], at index: inout Int) -> String? {
        var i = index
        guard i < characters.count else { return nil }

        if characters[i] == "<" {
            i += 1
            let start = i
            while i < characters.count, characters[i] != ">" {
                if characters[i] == "<" { return nil }
                if characters[i] == "\\" { i += 1 }
                i += 1
            }
            guard i < characters.count else { return nil }
            let destination = unescaped(characters[start..<i])
            index = i + 1
            return destination
        }

        let start = i
        var depth = 0
        while i < characters.count {
            let character = characters[i]
            if character == "\\" {
                i += 2
                continue
            }
            if character.isMarkdownSpace { break }
            if character == "(" { depth += 1 }
            if character == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            i += 1
        }
        guard depth == 0 else { return nil }
        i = min(i, characters.count)
        index = i
        return unescaped(characters[start..<i])
    }

    private static func titleCloser(for opener: Character) -> Character? {
        switch opener {
        case "\"": "\""
        case "'": "'"
        case "(": ")"
        default: nil
        }
    }

    private static func skipSpaces(_ characters: [Character], _ index: inout Int) {
        while index < characters.count, characters[index].isMarkdownSpace { index += 1 }
    }

    /// Drops the backslash from escaped ASCII punctuation.
    private static func unescaped(_ characters: ArraySlice<Character>) -> String {
        var result = ""
        var i = characters.startIndex
        while i < characters.endIndex {
            let character = characters[i]
            if character == "\\", i + 1 < characters.endIndex,
               let next = characters[i + 1].asciiValue, next.isASCIIPunctuation {
                result.append(characters[i + 1])
                i += 2
            } else {
                result.append(character)
                i += 1
            }
        }
        return result
    }

    private static func fenceMarker(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            return marker
        }
        return nil
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    private static func isHeading(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count < 4 else { return false }
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return false }
        let rest = trimmed.dropFirst(hashes.count)
        return rest.first.map(\.isMarkdownSpace) ?? true
    }

    /// A line of `=` or `-` that would make the paragraph above it a heading.
    private static func isSetextUnderline(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count < 4, let marker = trimmed.first, "=-".contains(marker) else { return false }
        let run = trimmed.prefix { $0 == marker }
        return trimmed.dropFirst(run.count).allSatisfy(\.isMarkdownSpace)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count < 4, let marker = trimmed.first, "-*_".contains(marker) else { return false }
        let characters = trimmed.filter { !$0.isMarkdownSpace }
        return characters.count >= 3 && characters.allSatisfy { $0 == marker }
    }
}

private extension Character {
    var isMarkdownSpace: Bool { self == " " || self == "\t" }
}

private extension UInt8 {
    var isASCIIPunctuation: Bool {
        (33...47).contains(self) || (58...64).contains(self) || (91...96).contains(self) || (123...126).contains(self)
    }
}

// MARK: - Metrics

/// Sizes of image blocks. Images fit the available width without being
/// scaled past their natural size, and very tall ones are capped.
public enum MarkdownImageMetrics {
    public static let cornerRadius: CGFloat = 8
    public static let maxHeight: CGFloat = 520
    /// Space between consecutive images in one paragraph.
    public static let spacing: CGFloat = 8
    /// Space between a gallery's thumbnails.
    public static let gallerySpacing: CGFloat = 4
    /// The largest a gallery's square thumbnails get.
    public static let galleryMaxThumbnailSide: CGFloat = 160
    /// Insets of the icon and text shown when an image can't load.
    public static let failurePadding = CGSize(width: 10, height: 6)
    public static let failureIconSpacing: CGFloat = 6

    /// The size an image of `naturalSize` points is shown at.
    public static func fittedSize(natural naturalSize: CGSize, availableWidth: CGFloat) -> CGSize {
        guard naturalSize.width > 0, naturalSize.height > 0, availableWidth > 0 else {
            return placeholderSize(availableWidth: availableWidth)
        }
        var width = min(naturalSize.width, availableWidth)
        var height = width * naturalSize.height / naturalSize.width
        if height > maxHeight {
            height = maxHeight
            width = height * naturalSize.width / naturalSize.height
        }
        return CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
    }

    /// The size of an image whose dimensions aren't known yet: 16:9 at full width.
    public static func placeholderSize(availableWidth: CGFloat) -> CGSize {
        let width = max(availableWidth, 0)
        let height = min(width * 9 / 16, maxHeight)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// Columns in a gallery of `count` images: up to three, or two by two for four.
    public static func galleryColumns(count: Int) -> Int {
        count == 4 ? 2 : max(1, min(count, 3))
    }

    /// The side of a gallery's square thumbnails: as wide as its columns
    /// fit, up to `galleryMaxThumbnailSide`.
    public static func galleryThumbnailSide(count: Int, availableWidth: CGFloat) -> CGFloat {
        let columns = CGFloat(galleryColumns(count: count))
        let fitted = (max(availableWidth, 0) - gallerySpacing * (columns - 1)) / columns
        return max(1, min(fitted, galleryMaxThumbnailSide).rounded(.down))
    }

    /// The size of a gallery's grid, which doesn't depend on its images, so
    /// it never moves as they load.
    public static func gallerySize(count: Int, availableWidth: CGFloat) -> CGSize {
        let columns = galleryColumns(count: count)
        let rows = (count + columns - 1) / columns
        let side = galleryThumbnailSide(count: count, availableWidth: availableWidth)
        return CGSize(
            width: side * CGFloat(columns) + gallerySpacing * CGFloat(columns - 1),
            height: side * CGFloat(rows) + gallerySpacing * CGFloat(max(rows - 1, 0))
        )
    }

    /// Where a gallery image's thumbnail sits in its gallery's grid, which
    /// starts at `origin` and is `width` wide.
    public static func galleryThumbnailFrame(
        at position: MarkdownImageGalleryPosition,
        origin: CGPoint,
        width: CGFloat
    ) -> CGRect {
        let columns = galleryColumns(count: position.count)
        let side = ((width - gallerySpacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        let column = position.index % columns
        let row = position.index / columns
        return CGRect(
            x: origin.x + CGFloat(column) * (side + gallerySpacing),
            y: origin.y + CGFloat(row) * (side + gallerySpacing),
            width: side,
            height: side
        )
    }

    /// The size of the row shown when an image can't load: a photo symbol
    /// and its label, on one line.
    public static func failureSize(label: String, fontSize: CGFloat, availableWidth: CGFloat) -> CGSize {
        let font = failureFont(fontSize: fontSize)
        // A little slack for the label's own insets, so it isn't truncated.
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width) + 4
        let iconWidth = ceil(font.pointSize * 1.25)
        let width = failurePadding.width * 2 + iconWidth + failureIconSpacing + textWidth
        let height = ceil(font.ascender - font.descender + font.leading) + failurePadding.height * 2
        return CGSize(width: min(width, max(availableWidth, 0)), height: height)
    }

    /// The size an image block takes up: the image fitted to the width once
    /// its size is known, a placeholder until then, or a row with its label
    /// if it can't load. A gallery image's line holds its whole gallery.
    static func layoutSize(
        of imageBlock: MarkdownImageBlock,
        state: MarkdownImageStore.LayoutState,
        displayScale: CGFloat,
        fontSize: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        if let gallery = imageBlock.gallery {
            return gallerySize(count: gallery.count, availableWidth: availableWidth)
        }
        switch state {
        case .loaded(let pixelSize):
            let scale = max(displayScale, 1)
            let naturalSize = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
            return fittedSize(natural: naturalSize, availableWidth: availableWidth)
        case .pending:
            return placeholderSize(availableWidth: availableWidth)
        case .failed:
            return failureSize(label: imageBlock.image.label, fontSize: fontSize, availableWidth: availableWidth)
        }
    }

    static func failureFont(fontSize: CGFloat) -> PlatformFont {
        .systemFont(ofSize: fontSize - 1)
    }
}
