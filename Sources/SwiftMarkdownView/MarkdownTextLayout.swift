#if !os(macOS)
import UIKit

/// Lays text out with TextKit 1 exactly as the overlaid `UITextView`s will,
/// so blocks can be sized before any view exists.
struct MarkdownTextLayout {
    /// A container width wide enough that code never wraps.
    static let unlimitedWidth: CGFloat = 10_000_000

    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private let textStorage: NSTextStorage

    init(_ text: NSAttributedString, width: CGFloat) {
        textStorage = NSTextStorage(attributedString: text)
        textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
    }

    var usedSize: CGSize {
        layoutManager.usedRect(for: textContainer).size
    }

    func height(ofCharacterRange range: NSRange) -> CGFloat {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var unionRect: CGRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            unionRect = unionRect.map { $0.union(lineRect) } ?? lineRect
        }
        return unionRect?.height ?? 0
    }

    /// A read-only, selectable text view configured to match this layout.
    @MainActor
    static func makeTextView() -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        return textView
    }
}
#endif
