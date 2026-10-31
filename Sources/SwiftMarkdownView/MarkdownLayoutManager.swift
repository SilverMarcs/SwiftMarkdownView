import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let verticalPadding: CGFloat = 16
        static let codeBlockHorizontalPadding: CGFloat = 10
        static let quoteIndentStep: CGFloat = 16
        static let quoteLineWidth: CGFloat = 3
        static let quoteLineInset: CGFloat = 6
        static let quoteVerticalInset: CGFloat = 2
    }

    public var codeBlocks: [MarkdownCodeBlock] = []
    public var codeBlockBackgroundColor: PlatformColor = .quaternarySystemFill
    public var quoteBlocks: [MarkdownQuoteBlock] = []
    public var quoteLineColor: PlatformColor = .markdownTertiaryLabel
    public var tableBlocks: [MarkdownTableBlock] = []
    public var imageBlocks: [MarkdownImageBlock] = []
    public var hasThematicBreaks = false
    /// The size to lay an image block out at, given the width available.
    var imageBlockSize: ((MarkdownImageBlock, CGFloat) -> CGSize)?

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawQuoteLines(forGlyphRange: glyphsToShow, at: origin)
        drawThematicBreaks(forGlyphRange: glyphsToShow, at: origin)
    }

    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        lineSpacingAfterGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: CGRect
    ) -> CGFloat {
        spacingAfterLineEndingGlyph(at: glyphIndex, keyPath: \.lineSpacing)
    }

    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        paragraphSpacingAfterGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: CGRect
    ) -> CGFloat {
        guard lineEndsParagraph(at: glyphIndex) else { return 0 }
        guard !lineEndsDocument(at: glyphIndex) else { return 0 }
        guard let paragraphStyle = paragraphStyle(at: glyphIndex) else { return 0 }
        return paragraphStyle.paragraphSpacing
    }

    /// Sizes the line holding an image block to fit the image.
    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard !imageBlocks.isEmpty,
              let imageBlockSize,
              let imageBlock = imageBlock(atGlyphIndex: glyphRange.location) else { return false }

        let size = imageBlockSize(imageBlock, lineFragmentRect.pointee.width - textContainer.lineFragmentPadding * 2)
        let extraHeight = size.height - lineFragmentUsedRect.pointee.height
        lineFragmentRect.pointee.size.height += extraHeight
        lineFragmentUsedRect.pointee.size = size
        baselineOffset.pointee += extraHeight
        return true
    }

    private func imageBlock(atGlyphIndex glyphIndex: Int) -> MarkdownImageBlock? {
        guard let textStorage else { return nil }
        let characterIndex = characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length,
              let id = textStorage.attribute(.markdownImageBlockID, at: characterIndex, effectiveRange: nil) as? Int else {
            return nil
        }
        // Blocks are numbered in order, so the ID is normally the index.
        if imageBlocks.indices.contains(id), imageBlocks[id].id == id {
            return imageBlocks[id]
        }
        return imageBlocks.first { $0.id == id }
    }

    /// Frames of the images laid out for image blocks, in text container coordinates.
    public func imageBlockFrames(in textContainer: NSTextContainer) -> [(imageBlock: MarkdownImageBlock, frame: CGRect)] {
        imageBlocks.compactMap { imageBlock in
            let glyphRange = glyphRange(forCharacterRange: imageBlock.range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }
            let usedRect = lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            guard !usedRect.isEmpty else { return nil }
            return (imageBlock, usedRect)
        }
    }

    /// Lays image blocks out again, after their sizes change.
    public func invalidateImageBlocks(_ blocks: [MarkdownImageBlock]) {
        guard let textStorage else { return }
        for block in blocks {
            let range = NSIntersectionRange(block.range, textStorage.fullRange)
            guard range.length > 0 else { continue }
            invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
    }

    private func drawCodeBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard !codeBlocks.isEmpty else { return }

        let visibleCharacterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Blocks with a layout are drawn by their own overlaid view.
        let visibleCodeBlocks = codeBlocks.filter {
            $0.layout == nil && NSIntersectionRange($0.range, visibleCharacterRange).length > 0
        }

        guard !visibleCodeBlocks.isEmpty else { return }

        for codeBlock in visibleCodeBlocks {
            let glyphRange = glyphRange(forCharacterRange: codeBlock.range, actualCharacterRange: nil)
            guard glyphRange.length > 0,
                  let blockRect = codeBlockRect(forGlyphRange: glyphRange, at: origin) else {
                continue
            }

            let path = PlatformBezierPath(roundedRect: blockRect, cornerRadius: Layout.cornerRadius)
            codeBlockBackgroundColor.setFill()
            path.fill()
            PlatformColor.markdownSeparator.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    public func codeBlockFrames(in textContainer: NSTextContainer) -> [(codeBlock: MarkdownCodeBlock, frame: CGRect)] {
        codeBlocks.compactMap { codeBlock in
            let glyphRange = glyphRange(forCharacterRange: codeBlock.range, actualCharacterRange: nil)
            guard glyphRange.length > 0,
                  let rect = codeBlockRect(forGlyphRange: glyphRange, at: .zero) else {
                return nil
            }
            return (codeBlock, rect)
        }
    }

    /// Frames of the blank lines reserved for tables, in text container coordinates.
    public func tableBlockFrames(in textContainer: NSTextContainer) -> [(tableBlock: MarkdownTableBlock, frame: CGRect)] {
        tableBlocks.compactMap { tableBlock in
            lineFragmentsRect(forCharacterRange: tableBlock.range).map { (tableBlock, $0) }
        }
    }

    /// Frames of the blank lines reserved for code blocks drawn by overlaid views.
    public func overlaidCodeBlockFrames(in textContainer: NSTextContainer) -> [(codeBlock: MarkdownCodeBlock, frame: CGRect)] {
        codeBlocks.compactMap { codeBlock in
            guard codeBlock.layout != nil else { return nil }
            return lineFragmentsRect(forCharacterRange: codeBlock.range).map { (codeBlock, $0) }
        }
    }

    private func lineFragmentsRect(forCharacterRange characterRange: NSRange) -> CGRect? {
        let glyphRange = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        var unionRect: CGRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            unionRect = unionRect.map { $0.union(lineRect) } ?? lineRect
        }
        return unionRect
    }

    private func codeBlockRect(
        forGlyphRange glyphRange: NSRange,
        at origin: CGPoint
    ) -> CGRect? {
        var unionRect: CGRect?
        var maxUsedWidth: CGFloat = 0

        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, _, effectiveGlyphRange, _ in
            guard NSIntersectionRange(effectiveGlyphRange, glyphRange).length > 0 else { return }
            let adjustedRect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            unionRect = unionRect.map { $0.union(adjustedRect) } ?? adjustedRect
            maxUsedWidth = max(maxUsedWidth, usedRect.maxX)
        }

        guard let unionRect else { return nil }

        let contentWidth = maxUsedWidth + Layout.codeBlockHorizontalPadding
        return CGRect(
            x: unionRect.minX,
            y: unionRect.minY - Layout.verticalPadding / 2,
            width: contentWidth,
            height: unionRect.height + Layout.verticalPadding
        ).integral
    }

    private func drawQuoteLines(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard !quoteBlocks.isEmpty, let textContainer = textContainers.first else { return }

        let visibleCharacterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let visibleQuoteBlocks = quoteBlocks.filter {
            NSIntersectionRange($0.range, visibleCharacterRange).length > 0
        }

        guard !visibleQuoteBlocks.isEmpty else { return }

        quoteLineColor.setFill()

        for quoteBlock in visibleQuoteBlocks {
            let glyphRange = glyphRange(forCharacterRange: quoteBlock.range, actualCharacterRange: nil)
            guard glyphRange.length > 0,
                  let blockRect = quoteBlockRect(forGlyphRange: glyphRange, in: textContainer, at: origin) else {
                continue
            }

            for level in 0..<quoteBlock.depth {
                let x = blockRect.minX + Layout.quoteLineInset + (CGFloat(level) * Layout.quoteIndentStep)
                let lineRect = CGRect(
                    x: x,
                    y: blockRect.minY + Layout.quoteVerticalInset,
                    width: Layout.quoteLineWidth,
                    height: max(0, blockRect.height - (Layout.quoteVerticalInset * 2))
                ).integral

                PlatformBezierPath(
                    roundedRect: lineRect,
                    cornerRadius: Layout.quoteLineWidth / 2
                ).fill()
            }
        }
    }

    private func quoteBlockRect(
        forGlyphRange glyphRange: NSRange,
        in textContainer: NSTextContainer,
        at origin: CGPoint
    ) -> CGRect? {
        var blockRect: CGRect?

        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, effectiveGlyphRange, _ in
            guard NSIntersectionRange(effectiveGlyphRange, glyphRange).length > 0 else { return }
            let adjustedRect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            blockRect = blockRect.map { $0.union(adjustedRect) } ?? adjustedRect
        }

        guard var blockRect else { return nil }

        blockRect.origin.x += textContainer.lineFragmentPadding
        blockRect.size.width = max(0, blockRect.size.width - (textContainer.lineFragmentPadding * 2))
        return blockRect.integral
    }

    private func drawThematicBreaks(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard hasThematicBreaks, let textStorage, let textContainer = textContainers.first else { return }

        let visibleCharRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard visibleCharRange.length > 0 else { return }

        textStorage.enumerateAttribute(.markdownThematicBreak, in: visibleCharRange) { value, range, _ in
            guard value != nil else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                let adjustedRect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
                let lineY = round(adjustedRect.midY)
                let lineX = adjustedRect.minX + textContainer.lineFragmentPadding
                let lineWidth = adjustedRect.width - (textContainer.lineFragmentPadding * 2)

                let linePath = PlatformBezierPath()
                linePath.move(to: CGPoint(x: lineX, y: lineY))
                linePath.addLineTo(CGPoint(x: lineX + lineWidth, y: lineY))
                linePath.lineWidth = 1
                PlatformColor.markdownSeparator.setStroke()
                linePath.stroke()
            }
        }
    }

    private func spacingAfterLineEndingGlyph(
        at glyphIndex: Int,
        keyPath: KeyPath<NSParagraphStyle, CGFloat>
    ) -> CGFloat {
        guard !lineEndsParagraph(at: glyphIndex) else { return 0 }
        guard let paragraphStyle = paragraphStyle(at: glyphIndex) else { return 0 }
        return paragraphStyle[keyPath: keyPath]
    }

    private func paragraphStyle(at glyphIndex: Int) -> NSParagraphStyle? {
        guard let textStorage else { return nil }
        let characterIndex = characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.paragraphStyle, at: characterIndex, effectiveRange: nil) as? NSParagraphStyle
    }

    private func lineEndsParagraph(at glyphIndex: Int) -> Bool {
        guard let textStorage else { return true }
        let string = textStorage.string as NSString
        let characterIndex = characterIndexForGlyph(at: glyphIndex)

        guard characterIndex < string.length else { return true }

        if string.character(at: characterIndex).isMarkdownParagraphTerminator {
            return true
        }

        let nextCharacterIndex = characterIndex + 1
        guard nextCharacterIndex < string.length else { return true }
        return string.character(at: nextCharacterIndex).isMarkdownParagraphTerminator
    }

    private func lineEndsDocument(at glyphIndex: Int) -> Bool {
        guard let textStorage else { return true }
        let string = textStorage.string as NSString
        let characterIndex = characterIndexForGlyph(at: glyphIndex)

        guard characterIndex < string.length else { return true }

        if !string.character(at: characterIndex).isMarkdownParagraphTerminator {
            return characterIndex == string.length - 1
        }

        let nextCharacterIndex = characterIndex + 1
        return nextCharacterIndex >= string.length
    }
}

private extension unichar {
    var isMarkdownParagraphTerminator: Bool {
        guard let scalar = UnicodeScalar(self) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
