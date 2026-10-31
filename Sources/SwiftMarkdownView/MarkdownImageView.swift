import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An embedded image, overlaid on the line the layout manager sizes for it.
/// Shows a placeholder while loading and the image's label if it can't load.
final class MarkdownImageView: PlatformView {
    enum Content {
        case loading
        case loaded(MarkdownImageAsset)
        case failed
    }

    var image: MarkdownImage {
        didSet {
            guard image != oldValue else { return }
            updateAccessibility()
            failureLabel?.text = image.label
        }
    }

    var content: Content = .loading {
        didSet { updateContent() }
    }

    var fillColor: PlatformColor = .quaternarySystemFill {
        didSet { updateFill() }
    }

    var fontSize: CGFloat = 13 {
        didSet {
            guard fontSize != oldValue else { return }
            failureLabel?.font = MarkdownImageMetrics.failureFont(fontSize: fontSize)
        }
    }

    /// Called with the image's source when it's tapped or clicked.
    var onTap: (@MainActor (String) -> Void)? {
        didSet { updateAccessibility() }
    }

    private var failureIcon: PlatformImageView?
    private var failureLabel: PlatformLabel?

    private var loadedAsset: MarkdownImageAsset? {
        if case .loaded(let asset) = content { asset } else { nil }
    }

    private var isTappable: Bool {
        onTap != nil && loadedAsset != nil
    }

    init(image: MarkdownImage) {
        self.image = image
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    private func updateContent() {
        let isFailed = if case .failed = content { true } else { false }
        if isFailed {
            makeFailureViewsIfNeeded()
        }
        failureIcon?.isHidden = !isFailed
        failureLabel?.isHidden = !isFailed
        updateFill()
        updateAccessibility()
    }

    private func makeFailureViewsIfNeeded() {
        guard failureIcon == nil else { return }
        let font = MarkdownImageMetrics.failureFont(fontSize: fontSize)

        #if os(macOS)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: font.pointSize, weight: .regular)
        icon.contentTintColor = .markdownSecondaryLabel
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: image.label)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        #else
        let icon = UIImageView(image: UIImage(systemName: "photo"))
        icon.preferredSymbolConfiguration = .init(font: font)
        icon.tintColor = .markdownSecondaryLabel
        icon.contentMode = .center
        let label = UILabel()
        label.text = image.label
        label.lineBreakMode = .byTruncatingMiddle
        #endif

        label.font = font
        label.textColor = .markdownSecondaryLabel
        addSubview(icon)
        addSubview(label)
        failureIcon = icon
        failureLabel = label
        layoutFailureViews()
    }

    private func layoutFailureViews() {
        guard let failureIcon, let failureLabel else { return }
        let padding = MarkdownImageMetrics.failurePadding
        let font = MarkdownImageMetrics.failureFont(fontSize: fontSize)
        let iconWidth = ceil(font.pointSize * 1.25)
        failureIcon.frame = CGRect(x: padding.width, y: 0, width: iconWidth, height: bounds.height)
        let labelX = padding.width + iconWidth + MarkdownImageMetrics.failureIconSpacing
        let labelHeight = ceil(font.ascender - font.descender + font.leading)
        failureLabel.frame = CGRect(
            x: labelX,
            y: ((bounds.height - labelHeight) / 2).rounded(),
            width: max(0, bounds.width - labelX - padding.width),
            height: labelHeight
        )
    }

    private func updateAccessibility() {
        #if os(macOS)
        setAccessibilityElement(true)
        setAccessibilityRole(isTappable ? .button : .image)
        setAccessibilityLabel(image.label)
        #else
        isAccessibilityElement = true
        accessibilityLabel = image.label
        accessibilityTraits = isTappable ? [.image, .button] : .image
        #endif
    }

    private func performTap() {
        guard isTappable else { return }
        onTap?(image.source)
    }

    private func copyImage() {
        guard let loadedAsset else { return }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([loadedAsset.platformImage])
        #else
        UIPasteboard.general.image = loadedAsset.platformImage
        #endif
    }

    // MARK: - Platform

    #if os(macOS)
    private var trackingArea: NSTrackingArea?

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.cornerRadius = MarkdownImageMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        updateAccessibility()
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    private func updateFill() {
        needsDisplay = true
    }

    override func updateLayer() {
        // The appearance is current here, so the fill resolves for it.
        if let loadedAsset {
            layer?.contents = loadedAsset.cgImage
            layer?.backgroundColor = nil
        } else {
            layer?.contents = nil
            layer?.backgroundColor = fillColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        layoutFailureViews()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if isTappable {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Claim the click so it doesn't start a text selection underneath.
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        performTap()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isTappable else { return false }
        performTap()
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let ancestorMenu = markdownAncestorMenu(from: self)
        guard loadedAsset != nil else { return ancestorMenu }

        let menu = (ancestorMenu?.copy() as? NSMenu) ?? NSMenu()
        let item = NSMenuItem(title: String(localized: "Copy Image"), action: #selector(copyImage(_:)), keyEquivalent: "")
        item.target = self
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func copyImage(_ sender: NSMenuItem) {
        copyImage()
    }
    #else
    private func commonInit() {
        clipsToBounds = true
        layer.cornerRadius = MarkdownImageMetrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.contentsGravity = .resizeAspectFill
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addInteraction(UIContextMenuInteraction(delegate: self))
        updateFill()
        updateAccessibility()
    }

    private func updateFill() {
        if let loadedAsset {
            layer.contents = loadedAsset.cgImage
            backgroundColor = nil
        } else {
            layer.contents = nil
            backgroundColor = fillColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutFailureViews()
    }

    @objc private func handleTap() {
        performTap()
    }

    override func accessibilityActivate() -> Bool {
        guard isTappable else { return false }
        performTap()
        return true
    }
    #endif
}

#if !os(macOS)
extension MarkdownImageView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard loadedAsset != nil else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Copy Image"), image: UIImage(systemName: "doc.on.doc")) { _ in
                    self?.copyImage()
                }
            ])
        })
    }
}
#endif

#if os(macOS)
private typealias PlatformImageView = NSImageView
private typealias PlatformLabel = NSTextField

private extension NSTextField {
    var text: String {
        get { stringValue }
        set { stringValue = newValue }
    }
}
#else
private typealias PlatformImageView = UIImageView
private typealias PlatformLabel = UILabel
#endif
