#if !os(macOS)
import UIKit

/// Horizontally scrolling code block overlaid on the blank line the renderer
/// reserves for it, so long lines scroll instead of wrapping. The code is a
/// selectable text view, which only renders the part that's on screen.
final class MarkdownCodeBlockView: UIScrollView {
    private let textView = MarkdownTextLayout.makeTextView()

    var codeLayout: MarkdownCodeLayout? {
        didSet {
            guard let codeLayout else { return }
            textView.attributedText = codeLayout.text
            let padding = MarkdownCodeLayout.padding
            textView.textContainerInset = UIEdgeInsets(top: padding.height, left: padding.width, bottom: padding.height, right: padding.width)
            textView.textContainer.size = CGSize(width: MarkdownTextLayout.unlimitedWidth, height: .greatestFiniteMagnitude)
            setNeedsLayout()
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
        layer.borderWidth = 1
        addSubview(textView)
        updateBorderColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MarkdownCodeBlockView, _) in
            view.updateBorderColor()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: max(codeLayout?.width ?? 0, bounds.width), height: bounds.height)
        if contentSize != size {
            contentSize = size
            textView.frame = CGRect(origin: .zero, size: size)
        }
    }

    private func updateBorderColor() {
        layer.borderColor = PlatformColor.markdownSeparator.resolvedColor(with: traitCollection).cgColor
    }
}
#endif
