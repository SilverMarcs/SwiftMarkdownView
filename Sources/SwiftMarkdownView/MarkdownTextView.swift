import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

#if os(macOS)

final class MarkdownPlainTextView: NSTextView, NSTextViewDelegate {
    var onOpenURL: ((URL) -> Void)?

    let markdownTextStorage = NSTextStorage()
    let markdownLayoutManager = MarkdownLayoutManager()
    let markdownTextContainer = NSTextContainer()

    init() {
        markdownLayoutManager.delegate = markdownLayoutManager
        markdownLayoutManager.addTextContainer(markdownTextContainer)
        markdownTextStorage.addLayoutManager(markdownLayoutManager)
        super.init(frame: .zero, textContainer: markdownTextContainer)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let ancestorMenu = markdownAncestorMenu(from: self)
        let point = convert(event.locationInWindow, from: nil)
        guard let link = link(at: point) else { return ancestorMenu }

        // Copy the inherited menu so link-specific items don't leak to other text.
        let menu = (ancestorMenu?.copy() as? NSMenu) ?? NSMenu()
        let item = NSMenuItem(title: String(localized: "Copy Link"), action: #selector(copyLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = link
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(item, at: 0)
        return menu
    }

    private func link(at point: NSPoint) -> String? {
        let textPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        markdownLayoutManager.ensureLayout(for: markdownTextContainer)
        let glyphIndex = markdownLayoutManager.glyphIndex(
            for: textPoint,
            in: markdownTextContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < markdownLayoutManager.numberOfGlyphs,
              markdownLayoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: markdownTextContainer
              ).contains(textPoint) else { return nil }

        let index = markdownLayoutManager.characterIndexForGlyph(at: glyphIndex)
        guard index < markdownTextStorage.length else { return nil }
        let value = markdownTextStorage.attribute(.link, at: index, effectiveRange: nil)
        return (value as? URL)?.absoluteString ?? (value as? String)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let onOpenURL else { return false }
        let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
        guard let url else { return false }
        onOpenURL(url)
        return true
    }

    override func copy(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }

        guard let payload = MarkdownCopyPayload.build(
            from: markdownTextStorage,
            tableBlocks: markdownLayoutManager.tableBlocks,
            imageBlocks: markdownLayoutManager.imageBlocks,
            selection: selection
        ) else {
            super.copy(sender)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload.plainText, forType: .string)
        if let htmlData = payload.html.data(using: .utf8) {
            pasteboard.setData(htmlData, forType: .html)
        }
    }

    func update(document: MarkdownRenderedDocument) {
        let preservedSelection = selectedRange()
        markdownLayoutManager.codeBlocks = document.codeBlocks
        markdownLayoutManager.quoteBlocks = document.quoteBlocks
        markdownLayoutManager.tableBlocks = document.tableBlocks
        markdownLayoutManager.imageBlocks = document.imageBlocks
        markdownLayoutManager.hasThematicBreaks = document.hasThematicBreaks
        markdownTextStorage.setAttributedString(document.attributedString)
        copyTableBlocks()
        fittedTableWidth = nil
        restoreSelectionIfNeeded(preservedSelection)
    }

    private func restoreSelectionIfNeeded(_ previous: NSRange) {
        guard previous.length > 0 else { return }
        let length = markdownTextStorage.length
        let location = min(previous.location, length)
        let maxLength = max(0, length - location)
        let clamped = NSRange(location: location, length: min(previous.length, maxLength))
        guard clamped.length > 0 else { return }
        setSelectedRange(clamped)
    }

    // MARK: - Tables

    private var fittedTableWidth: CGFloat?

    /// Sizes each table's columns to fill `width`, since `NSTextTable` can't
    /// size columns to their content itself.
    func fitTables(to width: CGFloat) {
        guard width != fittedTableWidth else { return }
        fittedTableWidth = width

        for table in markdownLayoutManager.tableBlocks where !table.columnWidthLimits.isEmpty {
            let columnWidths = table.columnWidths(fitting: width)
            let range = NSIntersectionRange(table.range, markdownTextStorage.fullRange)
            markdownTextStorage.enumerateAttribute(.paragraphStyle, in: range) { value, _, _ in
                guard let block = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock,
                      columnWidths.indices.contains(block.startingColumn) else { return }
                // The content width includes the cell's half-point borders.
                block.setContentWidth(columnWidths[block.startingColumn] + 1, type: .absoluteValueType)
            }
            markdownLayoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
    }

    /// Gives this view its own cell blocks, so fitting them to its width
    /// doesn't resize the same cached document shown in another view.
    private func copyTableBlocks() {
        let tables = markdownLayoutManager.tableBlocks.filter { !$0.columnWidthLimits.isEmpty }
        guard !tables.isEmpty else { return }

        var copies: [ObjectIdentifier: NSTextTableBlock] = [:]
        markdownTextStorage.beginEditing()
        for table in tables {
            let range = NSIntersectionRange(table.range, markdownTextStorage.fullRange)
            markdownTextStorage.enumerateAttribute(.paragraphStyle, in: range) { value, styleRange, _ in
                guard let style = value as? NSParagraphStyle,
                      let block = style.textBlocks.first as? NSTextTableBlock,
                      let copy = copies[ObjectIdentifier(block)] ?? block.copy() as? NSTextTableBlock,
                      let copiedStyle = style.mutableCopy() as? NSMutableParagraphStyle else { return }
                copies[ObjectIdentifier(block)] = copy
                copiedStyle.textBlocks = [copy]
                markdownTextStorage.addAttribute(.paragraphStyle, value: copiedStyle, range: styleRange)
            }
        }
        markdownTextStorage.endEditing()
    }

    func codeBlockFrames() -> [(codeBlock: MarkdownCodeBlock, frame: CGRect)] {
        markdownLayoutManager.codeBlockFrames(in: markdownTextContainer)
    }

    func imageBlockFrames() -> [(imageBlock: MarkdownImageBlock, frame: CGRect)] {
        markdownLayoutManager.imageBlockFrames(in: markdownTextContainer)
    }
}

public func markdownAncestorMenu(from view: NSView) -> NSMenu? {
    var currentView = unsafe view.superview

    while let candidate = currentView {
        if let menu = candidate.menu {
            return menu
        }

        currentView = unsafe candidate.superview
    }

    return nil
}

#else

final class MarkdownPlainTextView: UITextView {
    let markdownTextStorage = NSTextStorage()
    let markdownLayoutManager = MarkdownLayoutManager()
    let markdownTextContainer = NSTextContainer()

    init() {
        markdownLayoutManager.delegate = markdownLayoutManager
        markdownLayoutManager.addTextContainer(markdownTextContainer)
        markdownTextStorage.addLayoutManager(markdownLayoutManager)
        super.init(frame: .zero, textContainer: markdownTextContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func copy(_ sender: Any?) {
        let selection = selectedRange
        guard selection.length > 0 else { return }

        guard let payload = MarkdownCopyPayload.build(
            from: markdownTextStorage,
            tableBlocks: markdownLayoutManager.tableBlocks,
            codeBlocks: markdownLayoutManager.codeBlocks,
            imageBlocks: markdownLayoutManager.imageBlocks,
            selection: selection
        ) else {
            super.copy(sender)
            return
        }

        let pasteboard = UIPasteboard.general
        let htmlType = UTType.html.identifier
        let plainType = UTType.utf8PlainText.identifier
        pasteboard.items = [[
            plainType: payload.plainText,
            htmlType: payload.html
        ]]
    }

    func update(document: MarkdownRenderedDocument) {
        let preservedSelection = selectedRange
        markdownLayoutManager.codeBlocks = document.codeBlocks
        markdownLayoutManager.quoteBlocks = document.quoteBlocks
        markdownLayoutManager.tableBlocks = document.tableBlocks
        markdownLayoutManager.imageBlocks = document.imageBlocks
        markdownLayoutManager.hasThematicBreaks = document.hasThematicBreaks
        markdownTextStorage.setAttributedString(document.attributedString)
        restoreSelectionIfNeeded(preservedSelection)
    }

    private func restoreSelectionIfNeeded(_ previous: NSRange) {
        guard previous.length > 0 else { return }
        let length = markdownTextStorage.length
        let location = min(previous.location, length)
        let maxLength = max(0, length - location)
        let clamped = NSRange(location: location, length: min(previous.length, maxLength))
        guard clamped.length > 0 else { return }
        selectedRange = clamped
    }

    func codeBlockFrames() -> [(codeBlock: MarkdownCodeBlock, frame: CGRect)] {
        markdownLayoutManager.codeBlockFrames(in: markdownTextContainer)
    }

    func tableBlockFrames() -> [(tableBlock: MarkdownTableBlock, frame: CGRect)] {
        markdownLayoutManager.tableBlockFrames(in: markdownTextContainer)
    }

    func overlaidCodeBlockFrames() -> [(codeBlock: MarkdownCodeBlock, frame: CGRect)] {
        markdownLayoutManager.overlaidCodeBlockFrames(in: markdownTextContainer)
    }

    func imageBlockFrames() -> [(imageBlock: MarkdownImageBlock, frame: CGRect)] {
        markdownLayoutManager.imageBlockFrames(in: markdownTextContainer)
    }
}

#endif

// MARK: - Shared copy payload builder

struct MarkdownCopyPayload {
    let plainText: String
    let html: String

    static func build(
        from storage: NSTextStorage,
        tableBlocks: [MarkdownTableBlock],
        codeBlocks: [MarkdownCodeBlock] = [],
        imageBlocks: [MarkdownImageBlock] = [],
        selection: NSRange
    ) -> MarkdownCopyPayload? {
        // Tables, overlaid code blocks and images are blank placeholder lines in
        // the text, so their source is substituted when they're in the selection.
        let tableReplacements = tableBlocks.map { table in
            (range: table.range, representations: { tablePasteboardRepresentations(from: table.content) })
        }
        let codeReplacements = codeBlocks.filter { $0.layout != nil }.map { code in
            (range: code.range, representations: { (code.content, "<pre><code>\(htmlEscaped(code.content))</code></pre>") })
        }
        let imageReplacements = imageBlocks.map { block in
            (range: block.range, representations: { imagePasteboardRepresentations(of: block.image) })
        }
        let intersectingBlocks = (tableReplacements + codeReplacements + imageReplacements).filter {
            NSIntersectionRange($0.range, selection).length > 0
        }.sorted { $0.range.location < $1.range.location }

        let hasThematicBreaks = selectionContainsThematicBreak(in: storage, range: selection)

        guard !intersectingBlocks.isEmpty || hasThematicBreaks else { return nil }

        let fullString = storage.string as NSString
        let selEnd = selection.location + selection.length
        var plainText = ""
        var html = ""
        var cursor = selection.location

        for block in intersectingBlocks {
            let tableStart = block.range.location
            let tableEnd = block.range.location + block.range.length

            if cursor < tableStart {
                let pre = fullString.substring(with: NSRange(location: cursor, length: min(tableStart, selEnd) - cursor))
                plainText += pre
                html += htmlEscaped(pre)
            }

            let (tablePlain, tableHTML) = block.representations()
            plainText += tablePlain
            html += tableHTML
            cursor = min(tableEnd, selEnd)
        }

        if cursor < selEnd {
            let post = fullString.substring(with: NSRange(location: cursor, length: selEnd - cursor))
            plainText += post
            html += htmlEscaped(post)
        }

        if hasThematicBreaks {
            plainText = replaceThematicBreakCharacters(
                in: plainText,
                storage: storage,
                selectionRange: selection
            )
        }

        return MarkdownCopyPayload(plainText: plainText, html: html)
    }

    private static func selectionContainsThematicBreak(
        in storage: NSTextStorage,
        range: NSRange
    ) -> Bool {
        var found = false
        storage.enumerateAttribute(.markdownThematicBreak, in: range) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func replaceThematicBreakCharacters(
        in plainText: String,
        storage: NSTextStorage,
        selectionRange: NSRange
    ) -> String {
        var breakOffsets: [Int] = []
        storage.enumerateAttribute(.markdownThematicBreak, in: selectionRange) { value, range, _ in
            guard value != nil else { return }
            for i in 0..<range.length {
                breakOffsets.append(range.location + i - selectionRange.location)
            }
        }

        guard !breakOffsets.isEmpty else { return plainText }

        let breakSet = Set(breakOffsets)
        var result = ""
        var utf16Offset = 0
        for char in plainText {
            if breakSet.contains(utf16Offset) && char == "\u{200B}" {
                result += "---"
            } else {
                result += String(char)
            }
            utf16Offset += char.utf16.count
        }
        return result
    }

    private static func tablePasteboardRepresentations(from rawMarkdown: String) -> (plain: String, html: String) {
        let lines = rawMarkdown.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return (rawMarkdown, htmlEscaped(rawMarkdown)) }

        let headers = MarkdownTableBlock.parseCells(from: lines[0])
        let bodyLines = lines.dropFirst(MarkdownTableBlock.isSeparatorLine(lines[1]) ? 2 : 1)
        let rows = bodyLines.map { MarkdownTableBlock.parseCells(from: $0) }

        var plain = headers.joined(separator: "\t")
        for row in rows {
            plain += "\n" + row.joined(separator: "\t")
        }

        var html = "<table><thead><tr>"
        for header in headers {
            html += "<th>\(htmlEscaped(header))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for cell in row {
                html += "<td>\(htmlEscaped(cell))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"

        return (plain, html)
    }

    private static func imagePasteboardRepresentations(of image: MarkdownImage) -> (plain: String, html: String) {
        let needsBrackets = image.source.contains { $0.isWhitespace || $0 == "(" || $0 == ")" || $0 == "<" || $0 == ">" }
        let destination = needsBrackets
            ? "<" + image.source.replacing("<", with: "\\<").replacing(">", with: "\\>") + ">"
            : image.source
        let alt = image.altText.replacing("[", with: "\\[").replacing("]", with: "\\]")
        let html = "<img src=\"\(htmlEscaped(image.source))\" alt=\"\(htmlEscaped(image.altText))\">"
        return ("![\(alt)](\(destination))", html)
    }

    private static func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
