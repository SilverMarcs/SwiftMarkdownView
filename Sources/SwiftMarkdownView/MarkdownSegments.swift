import Foundation
import Synchronization
import SwiftUI

/// What a rendered segment was made from: its kind, its source and the block
/// IDs written into it. Two segments with the same key render identically,
/// wherever they sit in a document.
struct MarkdownSegmentKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case markdown
        case codeBlock(language: String?)
        case table
        case images
    }

    let kind: Kind
    let source: String
    /// The first code, table or image block ID the segment uses.
    let firstBlockID: Int
}

/// Where one segment's text sits in a rendered document, including the
/// spacer that follows a code block or table.
struct MarkdownSegmentSpan: Sendable {
    let key: MarkdownSegmentKey
    let range: NSRange
}

extension MarkdownSegmentSpan {
    /// Where two renders of a growing text start to differ: the end of the last
    /// segment they share. `nil` when they share none, so nothing can be kept.
    ///
    /// Segments render the same wherever they sit, so the text up to there is
    /// identical in both documents, and a text view showing `old` only needs
    /// what follows replaced.
    static func firstDifference(from old: [MarkdownSegmentSpan], to new: [MarkdownSegmentSpan]) -> Int? {
        var shared = 0
        while shared < old.count, shared < new.count, old[shared].key == new[shared].key {
            shared += 1
        }
        guard shared > 0 else { return nil }
        let end = NSMaxRange(old[shared - 1].range)
        guard end == NSMaxRange(new[shared - 1].range) else { return nil }
        return end
    }
}

enum MarkdownBlockSplitter {
    /// Splits lines of Markdown, outside fenced code and tables, into top-level
    /// blocks that render the same apart as together: a split falls only at a
    /// blank line before an unindented line that can't continue a list or a
    /// quote. A streaming reply then re-renders only its last block.
    static func blocks(_ lines: [String]) -> [[String]] {
        // A reference link's definition can sit far from the link it defines.
        guard !lines.contains(where: isLinkReferenceDefinition) else { return [lines] }

        var blocks: [[String]] = []
        var current: [String] = []
        var sawBlankLine = false
        var inHTMLComment = false

        for line in lines {
            let isBlank = line.allSatisfy(\.isWhitespace)
            if !isBlank, sawBlankLine, !inHTMLComment, startsTopLevelBlock(line), current.contains(where: { !$0.allSatisfy(\.isWhitespace) }) {
                blocks.append(current)
                current = []
            }
            current.append(line)
            if !isBlank {
                sawBlankLine = false
                if line.contains("<!--") { inHTMLComment = true }
                if line.contains("-->") { inHTMLComment = false }
            } else {
                sawBlankLine = true
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private static func startsTopLevelBlock(_ line: String) -> Bool {
        guard let first = line.first, !first.isWhitespace, first != ">" else { return false }
        return !isListItem(line)
    }

    private static func isListItem(_ line: String) -> Bool {
        let characters = Array(line.prefix(12))
        guard let first = characters.first else { return false }
        if first == "-" || first == "*" || first == "+" {
            return characters.count == 1 || characters[1] == " " || characters[1] == "\t"
        }
        var index = 0
        while index < characters.count, characters[index].isASCII, characters[index].isNumber { index += 1 }
        guard index > 0, index < characters.count, characters[index] == "." || characters[index] == ")" else { return false }
        return index + 1 == characters.count || characters[index + 1] == " " || characters[index + 1] == "\t"
    }

    private static func isLinkReferenceDefinition(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, trimmed.first == "[",
              let close = trimmed.firstIndex(of: "]") else { return false }
        return trimmed[trimmed.index(after: close)...].first == ":"
    }
}

/// Rendered segments shared by every render, so a streaming reply's finished
/// blocks are rendered once and every later render reuses the same text.
final class MarkdownSegmentCache: Sendable {
    struct Style: Hashable, Sendable {
        let fontSize: CGFloat
        let themeName: String
        let codeBlockBackground: Color
    }

    struct Key: Hashable, Sendable {
        let segment: MarkdownSegmentKey
        let style: Style
    }

    static let shared = MarkdownSegmentCache()

    private let limit = 2000
    private let storage = Mutex<[Key: MarkdownRenderedSegment]>([:])

    func segment(for key: Key) -> MarkdownRenderedSegment? {
        storage.withLock { $0[key] }
    }

    func store(_ segment: MarkdownRenderedSegment, for key: Key) {
        storage.withLock { segments in
            if segments.count >= limit { segments.removeAll(keepingCapacity: true) }
            segments[key] = segment
        }
    }
}

/// One segment's rendered text and the blocks in it, with ranges relative to
/// the segment's start.
struct MarkdownRenderedSegment: @unchecked Sendable {
    let attributedString: NSAttributedString
    var quoteBlocks: [MarkdownQuoteBlock] = []
    var hasThematicBreaks = false
    var codeLayout: MarkdownCodeLayout?
    var tableHeaderCharacterCount = 0
    var tableLayout: MarkdownTableLayout?
    var tableColumnWidthLimits: [ClosedRange<CGFloat>] = []
    var imageBlocks: [MarkdownImageBlock] = []
}
