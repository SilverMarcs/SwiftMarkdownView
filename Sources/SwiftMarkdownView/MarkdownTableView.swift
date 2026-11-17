#if !os(macOS)
import UIKit

/// Horizontally scrolling table overlaid on the blank line the renderer
/// reserves for it, so wide tables scroll instead of truncating. Each column
/// is a selectable text view; row stripes are plain colored views.
final class MarkdownTableView: UIScrollView {
    private let contentView = UIView()
    private var stripeViews: [UIView] = []
    private var columnViews: [UITextView] = []
    private let headerSeparator = UIView()

    var tableLayout: MarkdownTableLayout? {
        didSet {
            // A streaming reply sets every table's layout on each update;
            // a table that's done keeps its views, scroll and selection.
            if let tableLayout, let oldValue, tableLayout.hasSameContent(as: oldValue) { return }
            updateContent()
            setNeedsLayout()
        }
    }

    var stripeColor: UIColor = .quaternarySystemFill {
        didSet {
            for stripe in stripeViews {
                stripe.backgroundColor = stripeColor
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        clipsToBounds = true
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        headerSeparator.backgroundColor = .markdownSeparator
        headerSeparator.isHidden = true
        contentView.addSubview(headerSeparator)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var contentWidth: CGFloat {
        max(tableLayout?.width ?? 0, bounds.width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: contentWidth, height: bounds.height)
        guard contentSize != size else { return }
        contentSize = size
        contentView.frame = CGRect(origin: .zero, size: size)
        for stripe in stripeViews {
            stripe.frame.size.width = size.width
        }
        headerSeparator.frame.size.width = size.width
    }

    /// Updates the views to `tableLayout` in place. Emptying the table first
    /// would shrink its content size, which makes the scroll view clamp its
    /// offset: a table scrolled sideways jumped back each time a row streamed.
    private func updateContent() {
        let rowHeights = tableLayout?.rowHeights ?? []
        let columnTexts = tableLayout?.columnTexts ?? []
        let columnWidths = tableLayout?.columnWidths ?? []
        let width = contentWidth

        // Header and every other body row are shaded, matching macOS.
        var stripeFrames: [CGRect] = []
        var y: CGFloat = 0
        for (rowIndex, rowHeight) in rowHeights.enumerated() {
            if rowIndex.isMultiple(of: 2) {
                stripeFrames.append(CGRect(x: 0, y: y, width: width, height: rowHeight))
            }
            y += rowHeight
        }
        while stripeViews.count > stripeFrames.count {
            stripeViews.removeLast().removeFromSuperview()
        }
        while stripeViews.count < stripeFrames.count {
            let stripe = UIView()
            stripe.backgroundColor = stripeColor
            // Below the separator and the text.
            contentView.insertSubview(stripe, at: 0)
            stripeViews.append(stripe)
        }
        for (stripe, frame) in zip(stripeViews, stripeFrames) {
            stripe.frame = frame
        }

        if let headerHeight = rowHeights.first {
            let lineWidth = 1 / max(traitCollection.displayScale, 1)
            headerSeparator.frame = CGRect(x: 0, y: headerHeight - lineWidth, width: width, height: lineWidth)
            headerSeparator.isHidden = false
        } else {
            headerSeparator.isHidden = true
        }

        while columnViews.count > columnTexts.count {
            columnViews.removeLast().removeFromSuperview()
        }
        let padding = MarkdownTableLayout.cellPadding
        while columnViews.count < columnTexts.count {
            let textView = MarkdownTextLayout.makeTextView()
            textView.textContainerInset = UIEdgeInsets(top: padding.height, left: padding.width, bottom: 0, right: padding.width)
            contentView.addSubview(textView)
            columnViews.append(textView)
        }

        let height = tableLayout?.height ?? 0
        var x: CGFloat = 0
        for (column, textView) in columnViews.enumerated() {
            let columnWidth = columnWidths[column]
            let containerSize = CGSize(width: columnWidth - padding.width * 2, height: .greatestFiniteMagnitude)
            if textView.textContainer.size != containerSize {
                textView.textContainer.size = containerSize
            }
            let text = columnTexts[column]
            if let shown = textView.attributedText, shown === text || shown.isEqual(to: text) {
                // A column the update left alone keeps its layout and selection.
            } else {
                textView.attributedText = text
            }
            let frame = CGRect(x: x, y: 0, width: columnWidth, height: height)
            if textView.frame != frame {
                textView.frame = frame
            }
            x += columnWidth
        }
    }
}
#endif
