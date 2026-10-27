import Foundation
import Highlightr
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct MarkdownRenderedDocument: @unchecked Sendable {
    public let attributedString: NSAttributedString
    public let codeBlocks: [MarkdownCodeBlock]
    public let quoteBlocks: [MarkdownQuoteBlock]
    public let tableBlocks: [MarkdownTableBlock]
    public let hasThematicBreaks: Bool

    public init(
        attributedString: NSAttributedString,
        codeBlocks: [MarkdownCodeBlock],
        quoteBlocks: [MarkdownQuoteBlock],
        tableBlocks: [MarkdownTableBlock],
        hasThematicBreaks: Bool
    ) {
        self.attributedString = attributedString
        self.codeBlocks = codeBlocks
        self.quoteBlocks = quoteBlocks
        self.tableBlocks = tableBlocks
        self.hasThematicBreaks = hasThematicBreaks
    }
}

public struct MarkdownCodeBlock: Sendable {
    public let id: Int
    public let range: NSRange
    public let content: String
    /// Highlighted code drawn by the iOS code block view; `nil` on macOS,
    /// where the code is laid out inline and wraps.
    public let layout: MarkdownCodeLayout?

    public init(id: Int, range: NSRange, content: String, layout: MarkdownCodeLayout? = nil) {
        self.id = id
        self.range = range
        self.content = content
        self.layout = layout
    }
}

/// Highlighted code and its unwrapped size, for a horizontally scrolling block.
public struct MarkdownCodeLayout: @unchecked Sendable {
    /// Inset of the code from the block edges.
    public static let padding = CGSize(width: 12, height: 10)

    public let text: NSAttributedString
    public let textSize: CGSize

    public init(text: NSAttributedString, textSize: CGSize) {
        self.text = text
        self.textSize = textSize
    }

    public var width: CGFloat { textSize.width + Self.padding.width * 2 }
    public var height: CGFloat { textSize.height + Self.padding.height * 2 }
}

public struct MarkdownQuoteBlock: Sendable {
    public let range: NSRange
    public let depth: Int
    public let identity: Int

    public init(range: NSRange, depth: Int, identity: Int) {
        self.range = range
        self.depth = depth
        self.identity = identity
    }
}

public struct MarkdownTableBlock: Sendable {
    public let id: Int
    public let range: NSRange
    public let content: String
    public let headerCharacterCount: Int
    /// Pre-measured cells drawn by the iOS table view; `nil` on macOS, where
    /// the table is laid out inline with `NSTextTable`.
    public let layout: MarkdownTableLayout?

    public init(id: Int, range: NSRange, content: String, headerCharacterCount: Int, layout: MarkdownTableLayout? = nil) {
        self.id = id
        self.range = range
        self.content = content
        self.headerCharacterCount = headerCharacterCount
        self.layout = layout
    }

    public static func parseCells(from line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func isSeparatorLine(_ line: String) -> Bool {
        let cells = parseCells(from: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return !stripped.isEmpty && stripped.allSatisfy({ $0 == "-" })
        }
    }
}

/// Rendered cells and measured geometry for a table. The first row is the header.
public struct MarkdownTableLayout: @unchecked Sendable {
    /// Inset of cell text from the cell edges.
    public static let cellPadding = CGSize(width: 10, height: 6)
    /// Cells wider than this wrap instead of widening their column further.
    public static let maxCellTextWidth: CGFloat = 260

    /// One string per column, its cells as paragraphs spaced so each starts
    /// at the top of its row.
    public let columnTexts: [NSAttributedString]
    public let columnWidths: [CGFloat]
    public let rowHeights: [CGFloat]

    public init(columnTexts: [NSAttributedString], columnWidths: [CGFloat], rowHeights: [CGFloat]) {
        self.columnTexts = columnTexts
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
    }

    public var width: CGFloat { columnWidths.reduce(0, +) }
    public var height: CGFloat { rowHeights.reduce(0, +) }
}

public extension MarkdownRenderedDocument {
    static func placeholder(text: String, fontSize: CGFloat) -> MarkdownRenderedDocument {
        return MarkdownRenderedDocument(
            attributedString: plainTextFragment(text, fontSize: fontSize),
            codeBlocks: [],
            quoteBlocks: [],
            tableBlocks: [],
            hasThematicBreaks: false
        )
    }

    nonisolated(unsafe) private static let plainTextParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style.copy() as! NSParagraphStyle
    }()

    static func plainTextFragment(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        return NSAttributedString(
            string: text,
            attributes: [
                .font: PlatformFont.systemFont(ofSize: max(fontSize, 13), weight: .regular),
                .foregroundColor: PlatformColor.markdownLabel,
                .paragraphStyle: plainTextParagraphStyle
            ]
        )
    }
}

struct MarkdownHighlightedCode: @unchecked Sendable {
    let attributedString: NSAttributedString
}

actor MarkdownHighlighterPool {
    static let shared = MarkdownHighlighterPool()

    private var highlightersByTheme: [String: Highlightr] = [:]

    func highlightedCode(
        _ content: String,
        language: String?,
        themeName: String
    ) -> MarkdownHighlightedCode? {
        // Skip Highlightr when we don't know the language. Highlightr's default
        // path with a nil/unknown hint runs auto-detection, scoring every grammar
        // against the source — O(grammars × length) and brutal on large blocks.
        guard let hint = language?.lowercased(),
              let resolvedLanguage = Self.languageName(forHint: hint) else {
            return nil
        }

        let highlighter = highlighter(for: themeName)
        guard let highlighted = highlighter?.highlight(content, as: resolvedLanguage, fastRender: true) else {
            return nil
        }

        return MarkdownHighlightedCode(attributedString: highlighted)
    }

    private func highlighter(for themeName: String) -> Highlightr? {
        if let cachedHighlighter = highlightersByTheme[themeName] {
            return cachedHighlighter
        }

        let highlighter = Highlightr()
        highlighter?.setTheme(to: themeName)

        if let highlighter {
            highlightersByTheme[themeName] = highlighter
        }

        return highlighter
    }

    /// Maps a lowercased fence hint or file extension to a highlight.js language name.
    /// Returning nil signals the caller to fall back to plain monospace styling.
    private static func languageName(forHint hint: String) -> String? {
        switch hint {
        case "swift":                                          return "swift"
        case "js", "javascript", "jsx", "mjs", "node":         return "javascript"
        case "ts", "typescript", "tsx":                        return "typescript"
        case "py", "python", "python3":                        return "python"
        case "rb", "ruby":                                     return "ruby"
        case "rs", "rust":                                     return "rust"
        case "go", "golang":                                   return "go"
        case "c", "h":                                         return "c"
        case "cpp", "c++", "cxx", "cc", "hpp":                 return "cpp"
        case "objc", "objectivec", "objective-c", "m", "mm":   return "objectivec"
        case "java":                                           return "java"
        case "kt", "kotlin", "kts":                            return "kotlin"
        case "cs", "csharp", "c#":                             return "csharp"
        case "php":                                            return "php"
        case "sh", "bash", "shell", "shellscript", "zsh", "console": return "bash"
        case "html", "htm":                                    return "xml"
        case "xml", "svg", "plist":                            return "xml"
        case "css":                                            return "css"
        case "scss", "sass":                                   return "scss"
        case "less":                                           return "less"
        case "json":                                           return "json"
        case "yml", "yaml":                                    return "yaml"
        case "toml", "ini":                                    return "ini"
        case "md", "markdown":                                 return "markdown"
        case "sql":                                            return "sql"
        case "r":                                              return "r"
        case "lua":                                            return "lua"
        case "pl", "perl", "pm":                               return "perl"
        case "dart":                                           return "dart"
        case "ex", "elixir", "exs":                            return "elixir"
        case "erl", "erlang", "hrl":                           return "erlang"
        case "hs", "haskell":                                  return "haskell"
        case "scala":                                          return "scala"
        case "tf", "terraform", "hcl":                         return "hcl"
        case "dockerfile", "docker":                           return "dockerfile"
        case "makefile", "make", "mk":                         return "makefile"
        case "cmake":                                          return "cmake"
        case "groovy", "gradle":                               return "groovy"
        case "vim", "viml":                                    return "vim"
        case "proto", "protobuf":                              return "protobuf"
        case "graphql", "gql":                                 return "graphql"
        case "diff", "patch":                                  return "diff"
        default:                                               return nil
        }
    }
}

public struct MarkdownRenderer: Sendable {
    private enum Segment {
        case markdown(String)
        case codeBlock(String, language: String?)
        case table(headers: [String], rows: [[String]], rawContent: String)
    }

    private struct RenderedTextUnit {
        let attributedString: NSAttributedString
        let context: BlockContext
    }

    private struct BlockContext: Equatable {
        enum Kind: Equatable {
            case paragraph
            case heading(Int)
            case listItem(ListContext)
            case thematicBreak
        }

        struct ListContext: Equatable {
            enum Marker: Equatable {
                case bullet
                case ordered(Int)
            }

            let marker: Marker
            let level: Int
            let groupIdentity: Int
        }

        let kind: Kind
        let quoteDepth: Int
        let quoteIdentity: Int?
        let blockIdentity: Int
    }

    private enum ListMarker {
        case bullet
        case ordered(Int)
    }

    private struct MarkdownListContext {
        let marker: ListMarker
        let level: Int
        let groupIdentity: Int
    }

    private struct MarkdownPresentationContext {
        enum Kind {
            case paragraph
            case heading(Int)
            case thematicBreak
        }

        let kind: Kind
        let quoteDepth: Int
        let quoteIdentity: Int?
        let blockIdentity: Int
        let listContext: MarkdownListContext?
    }

    private let bodyFontSize: CGFloat
    private let codeFontSize: CGFloat
    private let themeName: String
    nonisolated(unsafe) let codeBlockBackground: PlatformColor
    private nonisolated(unsafe) let cachedDefaultParagraphStyle: NSParagraphStyle
    private nonisolated(unsafe) let cachedCodeBlockParagraphStyle: NSParagraphStyle
    private nonisolated(unsafe) let cachedCodeBlockSpacerStyle: NSParagraphStyle
    private nonisolated(unsafe) let cachedUnwrappedCodeParagraphStyle: NSParagraphStyle
    private nonisolated(unsafe) let cachedTableSpacerStyle: NSParagraphStyle
    private nonisolated(unsafe) let cachedBulletMarkerWidth: CGFloat

    public nonisolated init(fontSize: CGFloat, themeName: String, codeBlockBackground: Color = Color(PlatformColor.quaternarySystemFill)) {
        bodyFontSize = max(fontSize, 13)
        codeFontSize = max(bodyFontSize - 1, 12)
        self.themeName = themeName
        self.codeBlockBackground = PlatformColor(codeBlockBackground)

        let defaultStyle = NSMutableParagraphStyle()
        defaultStyle.lineSpacing = 4
        defaultStyle.paragraphSpacing = 0
        cachedDefaultParagraphStyle = defaultStyle.copy() as! NSParagraphStyle

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.lineSpacing = 3
        codeStyle.firstLineHeadIndent = 10
        codeStyle.headIndent = 10
        codeStyle.tailIndent = -10
        codeStyle.lineBreakMode = .byCharWrapping
        cachedCodeBlockParagraphStyle = codeStyle.copy() as! NSParagraphStyle

        // Clipping keeps each code line on a single line instead of wrapping.
        let unwrappedCodeStyle = NSMutableParagraphStyle()
        unwrappedCodeStyle.lineSpacing = 3
        unwrappedCodeStyle.lineBreakMode = .byClipping
        cachedUnwrappedCodeParagraphStyle = unwrappedCodeStyle.copy() as! NSParagraphStyle

        cachedCodeBlockSpacerStyle = Self.makeSpacerStyle(height: 8)
        cachedTableSpacerStyle = Self.makeSpacerStyle(height: 1)

        let bodyFont = PlatformFont.systemFont(ofSize: bodyFontSize, weight: .regular)
        cachedBulletMarkerWidth = ("•" as NSString).size(withAttributes: [.font: bodyFont]).width
    }

    private static func makeSpacerStyle(height: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style.copy() as! NSParagraphStyle
    }

    public nonisolated func render(_ markdown: String) async -> MarkdownRenderedDocument {
        let output = NSMutableAttributedString()
        var codeBlocks: [MarkdownCodeBlock] = []
        var quoteBlocks: [MarkdownQuoteBlock] = []
        var tableBlocks: [MarkdownTableBlock] = []
        var hasThematicBreaks = false
        var nextCodeBlockID = 0
        var nextTableBlockID = 0

        for segment in parseSegments(markdown) {
            let attributedSegment: NSAttributedString?
            var currentTableResult: RenderedTableResult?
            var currentCodeLayout: MarkdownCodeLayout?
            var segmentQuoteBlocks: [MarkdownQuoteBlock]?

            switch segment {
            case .markdown(let markdown):
                if let result = renderedMarkdownSegment(from: markdown) {
                    attributedSegment = result.attributedString
                    segmentQuoteBlocks = result.quoteBlocks
                    if result.hasThematicBreaks { hasThematicBreaks = true }
                } else {
                    attributedSegment = nil
                }
            case .codeBlock(let code, let language):
                let codeResult = await renderedCodeBlock(
                    content: code,
                    language: language,
                    blockID: nextCodeBlockID
                )
                attributedSegment = codeResult.attributedString
                currentCodeLayout = codeResult.layout
                nextCodeBlockID += 1
            case .table(let headers, let rows, _):
                let tableResult = renderedTableResult(
                    headers: headers,
                    rows: rows,
                    blockID: nextTableBlockID
                )
                currentTableResult = tableResult
                attributedSegment = tableResult.attributedString
                nextTableBlockID += 1
            }

            guard let attributedSegment, attributedSegment.length > 0 else { continue }

            if output.length > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }

            let range = NSRange(location: output.length, length: attributedSegment.length)
            output.append(attributedSegment)

            if case .codeBlock(let content, _) = segment {
                codeBlocks.append(
                    MarkdownCodeBlock(
                        id: nextCodeBlockID - 1,
                        range: range,
                        content: content,
                        layout: currentCodeLayout
                    )
                )
            }

            if case .table(_, _, let rawContent) = segment, let tableResult = currentTableResult {
                tableBlocks.append(
                    MarkdownTableBlock(
                        id: nextTableBlockID - 1,
                        range: range,
                        content: rawContent,
                        headerCharacterCount: tableResult.headerCharacterCount,
                        layout: tableResult.layout
                    )
                )
            }

            if let segmentQuoteBlocks {
                let offsetBlocks = segmentQuoteBlocks.map { block in
                    MarkdownQuoteBlock(
                        range: NSRange(location: block.range.location + range.location, length: block.range.length),
                        depth: block.depth,
                        identity: block.identity
                    )
                }
                mergeQuoteBlocks(&quoteBlocks, with: offsetBlocks)
            }

            switch segment {
            case .codeBlock:
                // The overlaid iOS block includes its own padding, so it needs no overhang.
                if currentCodeLayout == nil {
                    appendBlockOverhangSpacer(to: output, style: cachedCodeBlockSpacerStyle)
                }
            case .table:
                appendBlockOverhangSpacer(to: output, style: cachedTableSpacerStyle)
            default:
                break
            }
        }

        return MarkdownRenderedDocument(
            attributedString: output,
            codeBlocks: codeBlocks,
            quoteBlocks: quoteBlocks,
            tableBlocks: tableBlocks,
            hasThematicBreaks: hasThematicBreaks
        )
    }

    private nonisolated func appendBlockOverhangSpacer(to output: NSMutableAttributedString, style: NSParagraphStyle) {
        output.append(NSAttributedString(
            string: "\n\u{200B}",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 0.1),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: style
            ]
        ))
    }

    private struct RenderedMarkdownResult {
        let attributedString: NSAttributedString
        let quoteBlocks: [MarkdownQuoteBlock]
        let hasThematicBreaks: Bool
    }

    private nonisolated func renderedMarkdownSegment(from markdown: String) -> RenderedMarkdownResult? {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let result = styledMarkdown(markdown)
        guard result.attributedString.length > 0 else { return nil }
        return result
    }

    private nonisolated func renderedCodeBlock(
        content: String,
        language: String?,
        blockID: Int
    ) async -> (attributedString: NSAttributedString, layout: MarkdownCodeLayout?) {
        let codeFont = PlatformFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        let output: NSMutableAttributedString

        if let highlighted = await MarkdownHighlighterPool.shared.highlightedCode(
            content,
            language: language,
            themeName: themeName
        )?.attributedString {
            output = NSMutableAttributedString(attributedString: highlighted)
        } else {
            output = NSMutableAttributedString(
                string: content,
                attributes: [.foregroundColor: PlatformColor.markdownLabel]
            )
        }

        #if os(macOS)
        output.addAttributes([
            .font: codeFont,
            .paragraphStyle: codeBlockParagraphStyle(),
            .markdownCodeBlockID: blockID
        ], range: output.fullRange)

        return (output, nil)
        #else
        // iOS: code never wraps. The text reserves a blank line as tall as the
        // block and MarkdownContainerView overlays a horizontally scrolling
        // MarkdownCodeBlockView there.
        output.addAttributes([
            .font: codeFont,
            .paragraphStyle: cachedUnwrappedCodeParagraphStyle
        ], range: output.fullRange)

        let textLayout = MarkdownTextLayout(output, width: MarkdownTextLayout.unlimitedWidth)
        let layout = MarkdownCodeLayout(
            text: output,
            textSize: CGSize(width: ceil(textLayout.usedSize.width), height: ceil(textLayout.usedSize.height))
        )
        return (placeholderLine(height: layout.height, attribute: .markdownCodeBlockID, blockID: blockID), layout)
        #endif
    }

    private nonisolated func parseSegments(_ markdown: String) -> [Segment] {
        let lines = markdown.components(separatedBy: .newlines)
        var segments: [Segment] = []
        var markdownLines: [String] = []
        var index = 0

        func flushMarkdownLines() {
            let chunk = markdownLines.joined(separator: "\n")
            guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                markdownLines.removeAll(keepingCapacity: true)
                return
            }

            segments.append(.markdown(chunk))
            markdownLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushMarkdownLines()

                let language = parseCodeBlockLanguage(from: trimmed)
                var codeLines: [String] = []
                index += 1

                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    codeLines.append(lines[index])
                    index += 1
                }

                if index < lines.count {
                    index += 1
                }

                segments.append(.codeBlock(codeLines.joined(separator: "\n"), language: language))
                continue
            }

            if isTableRow(trimmed),
               index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                flushMarkdownLines()

                let headers = parseTableCells(trimmed)
                let separatorLine = lines[index + 1]
                var tableLines = [line, separatorLine]
                index += 2

                var rows: [[String]] = []
                while index < lines.count, isTableRow(lines[index]) {
                    rows.append(parseTableCells(lines[index]))
                    tableLines.append(lines[index])
                    index += 1
                }

                segments.append(.table(
                    headers: headers,
                    rows: rows,
                    rawContent: tableLines.joined(separator: "\n")
                ))
                continue
            }

            markdownLines.append(line)
            index += 1
        }

        flushMarkdownLines()
        return segments
    }

    private nonisolated func parseCodeBlockLanguage(from trimmedFenceLine: String) -> String? {
        let languageHint = trimmedFenceLine
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !languageHint.isEmpty else {
            return nil
        }

        return languageHint
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
    }

    private nonisolated func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.hasPrefix("```")
    }

    private nonisolated func isTableSeparator(_ line: String) -> Bool {
        MarkdownTableBlock.isSeparatorLine(line)
    }

    private nonisolated func parseTableCells(_ line: String) -> [String] {
        MarkdownTableBlock.parseCells(from: line)
    }

    private struct RenderedTableResult {
        let attributedString: NSAttributedString
        let headerCharacterCount: Int
        var layout: MarkdownTableLayout?
    }

    private nonisolated func renderedTableResult(
        headers: [String],
        rows: [[String]],
        blockID: Int
    ) -> RenderedTableResult {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else {
            return RenderedTableResult(
                attributedString: NSAttributedString(),
                headerCharacterCount: 0
            )
        }

        let paddedHeaders = headers + Array(repeating: "", count: max(0, columnCount - headers.count))
        let paddedRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }

        #if os(macOS)
        return renderedTableResultMac(
            paddedHeaders: paddedHeaders,
            paddedRows: paddedRows,
            columnCount: columnCount,
            blockID: blockID
        )
        #else
        return renderedTableResultScrollable(
            paddedHeaders: paddedHeaders,
            paddedRows: paddedRows,
            columnCount: columnCount,
            blockID: blockID
        )
        #endif
    }

    #if os(macOS)
    private nonisolated func renderedTableResultMac(
        paddedHeaders: [String],
        paddedRows: [[String]],
        columnCount: Int,
        blockID: Int
    ) -> RenderedTableResult {
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.setContentWidth(100, type: .percentageValueType)
        table.hidesEmptyCells = false
        table.collapsesBorders = true

        let headerFont = PlatformFont.systemFont(ofSize: bodyFontSize, weight: .semibold)
        let cellFont = bodyFont()

        let cellPadding: CGFloat = 16
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        for (col, header) in paddedHeaders.enumerated() {
            let width = (header as NSString).size(withAttributes: [.font: headerFont]).width + cellPadding
            columnWidths[col] = max(columnWidths[col], width)
        }
        for row in paddedRows {
            for (col, cell) in row.enumerated() {
                let width = (cell as NSString).size(withAttributes: [.font: cellFont]).width + cellPadding
                columnWidths[col] = max(columnWidths[col], width)
            }
        }
        let totalWidth = columnWidths.reduce(0, +)
        let columnPercentages: [CGFloat] = totalWidth > 0
            ? columnWidths.map { ($0 / totalWidth) * 100 }
            : [CGFloat](repeating: 100 / CGFloat(columnCount), count: columnCount)

        let alternateRowColor = codeBlockBackground
        let output = NSMutableAttributedString()

        func makeCellString(row: Int, col: Int, text: String, font: PlatformFont, isHeader: Bool) -> NSAttributedString {
            let block = NSTextTableBlock(
                table: table,
                startingRow: row,
                rowSpan: 1,
                startingColumn: col,
                columnSpan: 1
            )

            block.setContentWidth(columnPercentages[col], type: .percentageValueType)

            block.setWidth(5, type: .absoluteValueType, for: .padding, edge: .minY)
            block.setWidth(5, type: .absoluteValueType, for: .padding, edge: .maxY)
            block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minX)
            block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxX)

            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setBorderColor(.markdownSeparator)

            if isHeader {
                block.backgroundColor = alternateRowColor
            } else {
                block.backgroundColor = row % 2 == 0 ? alternateRowColor : .clear
            }

            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]
            style.lineSpacing = 2
            style.lineBreakMode = .byWordWrapping

            let cellContent: NSMutableAttributedString
            if let parsed = try? NSAttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                ),
                baseURL: nil
            ) {
                cellContent = NSMutableAttributedString(attributedString: parsed)
                normalizeFonts(in: cellContent)
                applyInlineCodeStyling(to: cellContent)
            } else {
                cellContent = NSMutableAttributedString(string: text)
            }

            let fullRange = NSRange(location: 0, length: cellContent.length)
            cellContent.addAttributes([
                .paragraphStyle: style,
                .markdownTableBlockID: blockID
            ], range: fullRange)

            cellContent.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                guard let existingFont = value as? PlatformFont else {
                    cellContent.addAttribute(.font, value: font, range: range)
                    return
                }
                let traits = existingFont.fontDescriptor.symbolicTraits
                if isHeader || traits.contains(.markdownBold) {
                    let weight: PlatformFont.Weight = .semibold
                    if traits.contains(.markdownMonoSpace) {
                        cellContent.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: existingFont.pointSize, weight: weight), range: range)
                    } else {
                        cellContent.addAttribute(.font, value: PlatformFont.systemFont(ofSize: font.pointSize, weight: weight), range: range)
                    }
                } else if !traits.contains(.markdownMonoSpace) {
                    cellContent.addAttribute(.font, value: font, range: range)
                }
            }

            cellContent.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if value == nil {
                    cellContent.addAttribute(.foregroundColor, value: PlatformColor.markdownLabel, range: range)
                }
            }

            cellContent.append(NSAttributedString(
                string: "\n",
                attributes: [
                    .font: font,
                    .foregroundColor: PlatformColor.markdownLabel,
                    .paragraphStyle: style,
                    .markdownTableBlockID: blockID
                ]
            ))

            return cellContent
        }

        var headerCharCount = 0
        for (col, header) in paddedHeaders.enumerated() {
            output.append(makeCellString(row: 0, col: col, text: header, font: headerFont, isHeader: true))
            headerCharCount += header.count + 1
        }

        for (rowIdx, row) in paddedRows.enumerated() {
            for (col, cell) in row.enumerated() {
                output.append(makeCellString(row: rowIdx + 1, col: col, text: cell, font: cellFont, isHeader: false))
            }
        }

        return RenderedTableResult(
            attributedString: output,
            headerCharacterCount: headerCharCount
        )
    }
    #endif

    #if !os(macOS)
    // iOS: NSTextTable / NSTextTableBlock are AppKit-only and not rendered by
    // UITextView's TextKit. Instead the text reserves a blank line as tall as the
    // table, and MarkdownContainerView overlays a horizontally scrolling
    // MarkdownTableView there that draws the pre-measured cells.
    private nonisolated func renderedTableResultScrollable(
        paddedHeaders: [String],
        paddedRows: [[String]],
        columnCount: Int,
        blockID: Int
    ) -> RenderedTableResult {
        let headerFont = PlatformFont.systemFont(ofSize: bodyFontSize, weight: .semibold)
        let cellFont = bodyFont()

        let cellStyle = NSMutableParagraphStyle()
        cellStyle.lineSpacing = 2
        cellStyle.lineBreakMode = .byWordWrapping

        func makeCell(_ text: String, font: PlatformFont, isHeader: Bool) -> NSAttributedString {
            let cellContent: NSMutableAttributedString
            if let parsed = try? NSAttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                ),
                baseURL: nil
            ) {
                cellContent = NSMutableAttributedString(attributedString: parsed)
                normalizeFonts(in: cellContent)
                applyInlineCodeStyling(to: cellContent)
            } else {
                cellContent = NSMutableAttributedString(string: text)
            }

            let fullRange = cellContent.fullRange
            cellContent.addAttribute(.paragraphStyle, value: cellStyle, range: fullRange)
            cellContent.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                guard let existing = value as? PlatformFont else {
                    cellContent.addAttribute(.font, value: font, range: range)
                    return
                }
                let traits = existing.fontDescriptor.symbolicTraits
                if isHeader || traits.contains(.markdownBold) {
                    let weight: PlatformFont.Weight = .semibold
                    if traits.contains(.markdownMonoSpace) {
                        cellContent.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: existing.pointSize, weight: weight), range: range)
                    } else {
                        cellContent.addAttribute(.font, value: PlatformFont.systemFont(ofSize: font.pointSize, weight: weight), range: range)
                    }
                } else if !traits.contains(.markdownMonoSpace) {
                    cellContent.addAttribute(.font, value: font, range: range)
                }
            }
            cellContent.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if value == nil {
                    cellContent.addAttribute(.foregroundColor, value: PlatformColor.markdownLabel, range: range)
                }
            }
            if cellContent.length == 0 {
                cellContent.append(NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: cellStyle]))
            }
            return cellContent
        }

        var rows = [paddedHeaders.map { makeCell($0, font: headerFont, isHeader: true) }]
        rows += paddedRows.map { row in row.map { makeCell($0, font: cellFont, isHeader: false) } }

        // Columns grow to fit their widest cell up to a cap, past which cells
        // wrap; the table scrolls horizontally when columns exceed the width.
        let padding = MarkdownTableLayout.cellPadding
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        for row in rows {
            for (col, cell) in row.enumerated() {
                let width = min(ceil(cell.size().width), MarkdownTableLayout.maxCellTextWidth)
                columnWidths[col] = max(columnWidths[col], width + padding.width * 2)
            }
        }

        // Each column is one text view: its cells are paragraphs. Lay each
        // column out once to measure its cells in place, then pad every
        // paragraph so the next cell starts at the top of its row.
        var columnTexts: [NSMutableAttributedString] = []
        var cellHeights = [[CGFloat]](repeating: [], count: columnCount)
        var paragraphRanges = [[NSRange]](repeating: [], count: columnCount)
        for col in 0..<columnCount {
            let text = NSMutableAttributedString()
            for (rowIndex, row) in rows.enumerated() {
                let start = text.length
                text.append(row[col])
                if rowIndex < rows.count - 1 {
                    text.append(NSAttributedString(string: "\n", attributes: row[col].attributes(at: row[col].length - 1, effectiveRange: nil)))
                }
                paragraphRanges[col].append(NSRange(location: start, length: text.length - start))
            }
            let textLayout = MarkdownTextLayout(text, width: columnWidths[col] - padding.width * 2)
            cellHeights[col] = paragraphRanges[col].map { textLayout.height(ofCharacterRange: $0) }
            columnTexts.append(text)
        }

        let rowHeights: [CGFloat] = rows.indices.map { rowIndex in
            ceil(cellHeights.map { $0[rowIndex] }.max() ?? 0) + padding.height * 2
        }

        for col in 0..<columnCount {
            for (rowIndex, range) in paragraphRanges[col].enumerated() {
                let style = cellStyle.mutableCopy() as! NSMutableParagraphStyle
                style.paragraphSpacing = rowHeights[rowIndex] - cellHeights[col][rowIndex]
                columnTexts[col].addAttribute(.paragraphStyle, value: style, range: range)
            }
        }

        let layout = MarkdownTableLayout(columnTexts: columnTexts, columnWidths: columnWidths, rowHeights: rowHeights)

        return RenderedTableResult(
            attributedString: placeholderLine(height: layout.height, attribute: .markdownTableBlockID, blockID: blockID),
            headerCharacterCount: 0,
            layout: layout
        )
    }

    /// An invisible line of a fixed height that reserves room for an overlaid view.
    private nonisolated func placeholderLine(height: CGFloat, attribute: NSAttributedString.Key, blockID: Int) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height

        return NSAttributedString(
            string: "\u{200B}",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 0.1),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: style,
                attribute: blockID
            ]
        )
    }
    #endif

    private nonisolated func styledMarkdown(_ markdown: String) -> RenderedMarkdownResult {
        let parsed: NSMutableAttributedString

        if let attributed = try? NSAttributedString(
            markdown: markdown,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            ),
            baseURL: nil
        ) {
            parsed = NSMutableAttributedString(attributedString: attributed)
        } else {
            parsed = NSMutableAttributedString(string: markdown)
        }

        let units = renderedTextUnits(from: parsed)
        let output = NSMutableAttributedString()
        var quoteBlocks: [MarkdownQuoteBlock] = []
        var hasThematicBreaks = false
        var index = 0

        while index < units.count {
            let unit = units[index]

            switch unit.context.kind {
            case .listItem(let listContext):
                if output.length > 0 {
                    output.append(NSAttributedString(string: "\n\n"))
                }

                let blockStart = output.length
                var isFirstItem = true
                while index < units.count {
                    guard case .listItem(let candidateContext) = units[index].context.kind,
                          candidateContext.groupIdentity == listContext.groupIdentity else {
                        break
                    }

                    if !isFirstItem {
                        output.append(NSAttributedString(string: "\n"))
                    }

                    output.append(styledListItem(units[index]))
                    isFirstItem = false
                    index += 1
                }

                if unit.context.quoteDepth > 0 {
                    let length = output.length - blockStart
                    if length > 0 {
                        quoteBlocks.append(MarkdownQuoteBlock(
                            range: NSRange(location: blockStart, length: length),
                            depth: unit.context.quoteDepth,
                            identity: unit.context.quoteIdentity ?? unit.context.blockIdentity
                        ))
                    }
                }

            default:
                if output.length > 0 {
                    output.append(NSAttributedString(string: "\n\n"))
                }

                if case .thematicBreak = unit.context.kind {
                    hasThematicBreaks = true
                }

                let blockStart = output.length
                output.append(styledBlock(unit))

                if unit.context.quoteDepth > 0 {
                    let length = output.length - blockStart
                    if length > 0 {
                        quoteBlocks.append(MarkdownQuoteBlock(
                            range: NSRange(location: blockStart, length: length),
                            depth: unit.context.quoteDepth,
                            identity: unit.context.quoteIdentity ?? unit.context.blockIdentity
                        ))
                    }
                }

                index += 1
            }
        }

        return RenderedMarkdownResult(attributedString: output, quoteBlocks: quoteBlocks, hasThematicBreaks: hasThematicBreaks)
    }

    private nonisolated func renderedTextUnits(from attributedString: NSAttributedString) -> [RenderedTextUnit] {
        let fullRange = attributedString.fullRange
        guard fullRange.length > 0 else { return [] }

        var units: [RenderedTextUnit] = []
        var currentContext: BlockContext?
        var currentString = NSMutableAttributedString()

        func flushCurrentUnit() {
            guard let currentContext, currentString.length > 0 else { return }
            units.append(
                RenderedTextUnit(
                    attributedString: NSAttributedString(attributedString: currentString),
                    context: currentContext
                )
            )
            currentString = NSMutableAttributedString()
        }

        attributedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let context = blockContext(for: attributes[.markdownPresentationIntent] as? PresentationIntent)
            let substring = NSMutableAttributedString(
                attributedString: attributedString.attributedSubstring(from: range)
            )
            substring.removeAttribute(.markdownPresentationIntent, range: substring.fullRange)
            substring.removeAttribute(.markdownListItemDelimiter, range: substring.fullRange)

            if currentContext == context {
                currentString.append(substring)
            } else {
                flushCurrentUnit()
                currentContext = context
                currentString = substring
            }
        }

        flushCurrentUnit()
        return units
    }

    private nonisolated func blockContext(for presentationIntent: PresentationIntent?) -> BlockContext {
        let context = presentationContext(for: presentationIntent)

        if let listContext = context.listContext {
            return BlockContext(
                kind: .listItem(
                    .init(
                        marker: listMarker(for: listContext.marker),
                        level: listContext.level,
                        groupIdentity: listContext.groupIdentity
                    )
                ),
                quoteDepth: context.quoteDepth,
                quoteIdentity: context.quoteIdentity,
                blockIdentity: context.blockIdentity
            )
        }

        let kind: BlockContext.Kind
        switch context.kind {
        case .paragraph:
            kind = .paragraph
        case .heading(let level):
            kind = .heading(level)
        case .thematicBreak:
            kind = .thematicBreak
        }

        return BlockContext(
            kind: kind,
            quoteDepth: context.quoteDepth,
            quoteIdentity: context.quoteIdentity,
            blockIdentity: context.blockIdentity
        )
    }

    private nonisolated func presentationContext(for presentationIntent: PresentationIntent?) -> MarkdownPresentationContext {
        let components = presentationIntent?.components ?? []
        let quoteIdentity = components.first { component in
            if case .blockQuote = component.kind {
                true
            } else {
                false
            }
        }?.identity
        let quoteDepth = components.reduce(into: 0) { count, component in
            if case .blockQuote = component.kind {
                count += 1
            }
        }

        if let thematicBreak = components.first(where: isThematicBreak) {
            return MarkdownPresentationContext(
                kind: .thematicBreak,
                quoteDepth: quoteDepth,
                quoteIdentity: quoteIdentity,
                blockIdentity: thematicBreak.identity,
                listContext: nil
            )
        }

        if let header = components.first(where: isHeader) {
            guard case let .header(level) = header.kind else {
                return MarkdownPresentationContext(
                    kind: .paragraph,
                    quoteDepth: quoteDepth,
                    quoteIdentity: quoteIdentity,
                    blockIdentity: header.identity,
                    listContext: nil
                )
            }

            return MarkdownPresentationContext(
                kind: .heading(level),
                quoteDepth: quoteDepth,
                quoteIdentity: quoteIdentity,
                blockIdentity: header.identity,
                listContext: nil
            )
        }

        let paragraph = components.first(where: isParagraph)
        let listItem = components.first(where: isListItem)
        let list = components.first(where: isList)

        let listContext: MarkdownListContext?
        if let listItem, let list {
            let marker: ListMarker
            switch (list.kind, listItem.kind) {
            case (.orderedList, .listItem(let ordinal)):
                marker = .ordered(ordinal)
            default:
                marker = .bullet
            }

            listContext = MarkdownListContext(
                marker: marker,
                level: max(presentationIntent?.indentationLevel ?? 1, 1),
                groupIdentity: list.identity
            )
        } else {
            listContext = nil
        }

        return MarkdownPresentationContext(
            kind: .paragraph,
            quoteDepth: quoteDepth,
            quoteIdentity: quoteIdentity,
            blockIdentity: paragraph?.identity ?? components.first?.identity ?? 0,
            listContext: listContext
        )
    }

    private nonisolated func isParagraph(_ component: PresentationIntent.IntentType) -> Bool {
        if case .paragraph = component.kind { true } else { false }
    }

    private nonisolated func isHeader(_ component: PresentationIntent.IntentType) -> Bool {
        if case .header = component.kind { true } else { false }
    }

    private nonisolated func isList(_ component: PresentationIntent.IntentType) -> Bool {
        switch component.kind {
        case .orderedList, .unorderedList: true
        default: false
        }
    }

    private nonisolated func isListItem(_ component: PresentationIntent.IntentType) -> Bool {
        if case .listItem = component.kind { true } else { false }
    }

    private nonisolated func isThematicBreak(_ component: PresentationIntent.IntentType) -> Bool {
        if case .thematicBreak = component.kind { true } else { false }
    }

    private nonisolated func styledBlock(_ unit: RenderedTextUnit) -> NSAttributedString {
        switch unit.context.kind {
        case .listItem:
            return styledListItem(unit)
        case .thematicBreak:
            return thematicBreakAttributedString(quoteDepth: unit.context.quoteDepth)
        case .paragraph, .heading:
            let output = NSMutableAttributedString(attributedString: unit.attributedString)
            normalizeFonts(in: output)

            let paragraphStyle = paragraphStyle(
                paragraphStyle(),
                adjustedForQuoteDepth: unit.context.quoteDepth
            )
            let foregroundColor = unit.context.quoteDepth > 0 ? quoteTextColor() : PlatformColor.markdownLabel

            output.addAttribute(.paragraphStyle, value: paragraphStyle, range: output.fullRange)
            output.addAttribute(.foregroundColor, value: foregroundColor, range: output.fullRange)

            if case .heading(let level) = unit.context.kind {
                output.addAttribute(.font, value: headingFont(for: level), range: output.fullRange)
            }

            applyInlineCodeStyling(to: output)
            return output
        }
    }

    private nonisolated func styledListItem(_ unit: RenderedTextUnit) -> NSAttributedString {
        guard case .listItem(let listContext) = unit.context.kind else {
            return styledBlock(unit)
        }

        let marker = markerText(for: listContext.marker)
        let markerIndent = CGFloat(max(0, listContext.level - 1)) * 20
        let style = paragraphStyle(
            listParagraphStyle(markerIndent: markerIndent, marker: marker),
            adjustedForQuoteDepth: unit.context.quoteDepth
        )
        let foregroundColor = unit.context.quoteDepth > 0 ? quoteTextColor() : PlatformColor.markdownLabel

        let output = NSMutableAttributedString(
            string: "\(marker)\t",
            attributes: [
                .font: bodyFont(),
                .paragraphStyle: style,
                .foregroundColor: foregroundColor
            ]
        )

        let content = NSMutableAttributedString(attributedString: unit.attributedString)
        normalizeFonts(in: content)
        content.addAttribute(.paragraphStyle, value: style, range: content.fullRange)
        content.addAttribute(.foregroundColor, value: foregroundColor, range: content.fullRange)
        applyInlineCodeStyling(to: content)

        output.append(content)
        return output
    }

    private nonisolated func thematicBreakAttributedString(quoteDepth: Int) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 16
        style.maximumLineHeight = 16
        let adjustedStyle = paragraphStyle(style, adjustedForQuoteDepth: quoteDepth)

        return NSAttributedString(
            string: "\u{200B}",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 1),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: adjustedStyle,
                .markdownThematicBreak: true
            ]
        )
    }

    private nonisolated func listMarker(for marker: ListMarker) -> BlockContext.ListContext.Marker {
        switch marker {
        case .bullet:
            return .bullet
        case .ordered(let value):
            return .ordered(value)
        }
    }

    private nonisolated func normalizeFonts(in attributedString: NSMutableAttributedString) {
        let fullRange = attributedString.fullRange

        if fullRange.length == 0 {
            return
        }

        attributedString.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? PlatformFont else {
                attributedString.addAttribute(.font, value: bodyFont(), range: range)
                return
            }

            let traits = font.fontDescriptor.symbolicTraits

            guard !traits.contains(.markdownMonoSpace) else { return }

            let weight: PlatformFont.Weight = traits.contains(.markdownBold) ? .semibold : .regular
            attributedString.addAttribute(.font, value: PlatformFont.systemFont(ofSize: bodyFontSize, weight: weight), range: range)
        }
    }

    private nonisolated func applyInlineCodeStyling(to attributedString: NSMutableAttributedString) {
        let fullRange = attributedString.fullRange
        guard fullRange.length > 0 else { return }

        attributedString.enumerateAttribute(.markdownInlinePresentationIntent, in: fullRange) { value, range, _ in
            let isInlineCode: Bool
            if let intent = value as? InlinePresentationIntent {
                isInlineCode = intent.contains(.code)
            } else {
                let rawValue = (value as? NSNumber)?.intValue ?? 0
                isInlineCode = rawValue & 4 != 0
            }

            guard isInlineCode else {
                return
            }

            let weight: PlatformFont.Weight
            if let existingFont = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont,
               existingFont.fontDescriptor.symbolicTraits.contains(.markdownBold) {
                weight = .semibold
            } else {
                weight = .regular
            }

            attributedString.addAttributes([
                .font: PlatformFont.monospacedSystemFont(ofSize: codeFontSize, weight: weight),
                .foregroundColor: PlatformColor.markdownAccent
            ], range: range)
        }
    }

    private nonisolated func codeBlockParagraphStyle() -> NSParagraphStyle {
        cachedCodeBlockParagraphStyle
    }

    private nonisolated func mergeQuoteBlocks(_ quoteBlocks: inout [MarkdownQuoteBlock], with newBlocks: [MarkdownQuoteBlock]) {
        for block in newBlocks {
            guard let lastBlock = quoteBlocks.last else {
                quoteBlocks.append(block)
                continue
            }

            let lastBlockEnd = lastBlock.range.location + lastBlock.range.length
            let gapLength = block.range.location - lastBlockEnd

            if lastBlock.identity == block.identity,
               lastBlock.depth == block.depth,
               gapLength >= 0,
               gapLength <= 2 {
                quoteBlocks[quoteBlocks.count - 1] = MarkdownQuoteBlock(
                    range: NSRange(
                        location: lastBlock.range.location,
                        length: (block.range.location + block.range.length) - lastBlock.range.location
                    ),
                    depth: block.depth,
                    identity: block.identity
                )
            } else {
                quoteBlocks.append(block)
            }
        }
    }

    private nonisolated func markerText(for marker: BlockContext.ListContext.Marker) -> String {
        switch marker {
        case .bullet: "•"
        case .ordered(let value): "\(value)."
        }
    }

    private nonisolated func paragraphStyle() -> NSParagraphStyle {
        cachedDefaultParagraphStyle
    }

    private nonisolated func quoteTextColor() -> PlatformColor {
        PlatformColor.markdownSecondaryLabel
    }

    private nonisolated func listParagraphStyle(markerIndent: CGFloat, marker: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let markerWidth: CGFloat
        if marker == "•" {
            markerWidth = cachedBulletMarkerWidth
        } else {
            markerWidth = (marker as NSString).size(withAttributes: [.font: bodyFont()]).width
        }
        let contentIndent = markerIndent + markerWidth + 10
        style.firstLineHeadIndent = markerIndent
        style.headIndent = contentIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: contentIndent)]
        style.defaultTabInterval = contentIndent
        style.paragraphSpacing = 5
        return style
    }

    private nonisolated func paragraphStyle(
        _ baseStyle: NSParagraphStyle,
        adjustedForQuoteDepth quoteDepth: Int
    ) -> NSParagraphStyle {
        guard quoteDepth > 0 else { return baseStyle }

        let style = baseStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        let quoteIndent = CGFloat(quoteDepth) * 16
        style.headIndent += quoteIndent
        style.firstLineHeadIndent += quoteIndent
        style.paragraphSpacing = max(style.paragraphSpacing, 4)
        style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, 2)
        return style
    }

    private nonisolated func headingFont(for level: Int) -> PlatformFont {
        switch level {
        case 1: return .systemFont(ofSize: bodyFontSize + 11, weight: .bold)
        case 2: return .systemFont(ofSize: bodyFontSize + 6, weight: .bold)
        case 3: return .systemFont(ofSize: bodyFontSize + 3, weight: .semibold)
        case 4: return .systemFont(ofSize: bodyFontSize, weight: .semibold)
        default: return .systemFont(ofSize: bodyFontSize, weight: .regular)
        }
    }

    private nonisolated func bodyFont() -> PlatformFont {
        .systemFont(ofSize: bodyFontSize, weight: .regular)
    }
}

public extension NSAttributedString.Key {
    fileprivate nonisolated static let markdownInlinePresentationIntent = Self("NSInlinePresentationIntent")
    fileprivate nonisolated static let markdownListItemDelimiter = Self("NSListItemDelimiter")
    fileprivate nonisolated static let markdownPresentationIntent = Self("NSPresentationIntent")
    nonisolated static let markdownCodeBlockID = Self("SwiftMarkdownViewCodeBlockID")
    nonisolated static let markdownTableBlockID = Self("SwiftMarkdownViewTableBlockID")
    nonisolated static let markdownThematicBreak = Self("SwiftMarkdownViewThematicBreak")
}
