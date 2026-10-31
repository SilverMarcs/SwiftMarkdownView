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

/// An image shown as its own block, from a paragraph made only of images.
/// Its range is a single invisible character on a line the layout manager
/// sizes to fit the image, where `MarkdownContainerView` overlays it.
public struct MarkdownImageBlock: Sendable {
    public let id: Int
    public let range: NSRange
    public let image: MarkdownImage

    public init(id: Int, range: NSRange, image: MarkdownImage) {
        self.id = id
        self.range = range
        self.image = image
    }
}

// MARK: - Syntax

/// Finds paragraphs made only of images, which render as image blocks.
/// Images inside a sentence are left to Foundation, which shows their alt text.
enum MarkdownImageSyntax {
    enum Piece: Equatable {
        case markdown([String])
        case images([MarkdownImage])
    }

    /// Splits lines of Markdown, outside fenced code and tables, into runs of
    /// Markdown and paragraphs made only of images.
    static func split(_ lines: [String]) -> [Piece] {
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
            if startsParagraph, var images = images(inLine: line) {
                var end = index + 1
                while end < lines.count, let more = self.images(inLine: lines[end]) {
                    images += more
                    end += 1
                }
                // Any other text on the next line would continue the paragraph.
                if end == lines.count || isBlank(lines[end]) || isHeading(lines[end])
                    || (isThematicBreak(lines[end]) && !lines[end].contains("-")) {
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

    static func failureFont(fontSize: CGFloat) -> PlatformFont {
        .systemFont(ofSize: max(fontSize, 13) - 1)
    }
}
