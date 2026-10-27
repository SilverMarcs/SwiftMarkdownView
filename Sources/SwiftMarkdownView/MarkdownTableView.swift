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
            rebuildContent()
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
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: max(tableLayout?.width ?? 0, bounds.width), height: bounds.height)
        guard contentSize != size else { return }
        contentSize = size
        contentView.frame = CGRect(origin: .zero, size: size)
        for stripe in stripeViews {
            stripe.frame.size.width = size.width
        }
        headerSeparator.frame.size.width = size.width
    }

    private func rebuildContent() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        stripeViews = []
        columnViews = []
        contentSize = .zero
        guard let tableLayout else { return }

        // Header and every other body row are shaded, matching macOS.
        var y: CGFloat = 0
        for (rowIndex, rowHeight) in tableLayout.rowHeights.enumerated() {
            if rowIndex.isMultiple(of: 2) {
                let stripe = UIView(frame: CGRect(x: 0, y: y, width: 0, height: rowHeight))
                stripe.backgroundColor = stripeColor
                contentView.addSubview(stripe)
                stripeViews.append(stripe)
            }
            y += rowHeight
        }

        if let headerHeight = tableLayout.rowHeights.first {
            let lineWidth = 1 / max(traitCollection.displayScale, 1)
            headerSeparator.frame = CGRect(x: 0, y: headerHeight - lineWidth, width: 0, height: lineWidth)
            contentView.addSubview(headerSeparator)
        }

        let padding = MarkdownTableLayout.cellPadding
        var x: CGFloat = 0
        for (column, text) in tableLayout.columnTexts.enumerated() {
            let width = tableLayout.columnWidths[column]
            let textView = MarkdownTextLayout.makeTextView()
            textView.textContainerInset = UIEdgeInsets(top: padding.height, left: padding.width, bottom: 0, right: padding.width)
            textView.textContainer.size = CGSize(width: width - padding.width * 2, height: .greatestFiniteMagnitude)
            textView.attributedText = text
            textView.frame = CGRect(x: x, y: 0, width: width, height: tableLayout.height)
            contentView.addSubview(textView)
            columnViews.append(textView)
            x += width
        }
    }
}
#endif
