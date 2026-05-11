import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class MarkdownContainerView: PlatformView {
    fileprivate enum Layout {
        #if os(macOS)
        static let copyButtonInset: CGFloat = 4
        static let copyButtonSize: CGFloat = 23
        #else
        static let copyButtonInset: CGFloat = 6
        static let copyButtonSize: CGFloat = 18
        #endif
    }

    fileprivate let textView = MarkdownPlainTextView()
    fileprivate var currentWidth: CGFloat = 0
    fileprivate var lastReportedHeight: CGFloat = 0
    fileprivate var lastMeasuredSize: CGSize = .zero
    fileprivate var currentDocument: MarkdownRenderedDocument?
    fileprivate var currentRequest: MarkdownRenderRequest?
    fileprivate var currentThemeName: String?
    fileprivate var isShowingPlaceholder = false
    fileprivate var isShowingStreamedContent = false
    fileprivate var needsMeasurement = false
    fileprivate var cachedCodeBlockFrames: [(codeBlock: MarkdownCodeBlock, frame: CGRect)] = []

    var onThemeChange: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    var codeBlockBackground: PlatformColor = .quaternarySystemFill {
        didSet {
            guard codeBlockBackground != oldValue else { return }
            textView.markdownLayoutManager.codeBlockBackgroundColor = codeBlockBackground
            #if os(macOS)
            textView.needsDisplay = true
            #else
            textView.setNeedsDisplay()
            #endif
        }
    }

    var codeTheme: MarkdownCodeTheme = .default {
        didSet {
            guard codeTheme != oldValue else { return }
            let newName = resolvedThemeName
            guard currentThemeName != newName else { return }
            currentThemeName = newName
            onThemeChange?(newName)
        }
    }

    fileprivate var widthConstraint: NSLayoutConstraint?

    #if os(macOS)
    private var codeBlockButtons: [Int: NSButton] = [:]
    private var hoveredCodeBlockID: Int?
    private var trackingArea: NSTrackingArea?
    #else
    private var codeBlockButtons: [Int: UIButton] = [:]
    #endif

    // MARK: - Init

    #if os(macOS)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    override var isFlipped: Bool { true }
    #else
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        #if os(macOS)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        #else
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        // UITextView's selection menu defaults already include Copy.
        #endif

        textView.markdownTextContainer.lineFragmentPadding = 0
        textView.markdownTextContainer.widthTracksTextView = true
        textView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textView)

        let widthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint
        ])
    }

    // MARK: - Layout

    #if os(macOS)
    override func layout() {
        super.layout()
        performLayoutPass()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        performLayoutPass()
    }
    #endif

    private func performLayoutPass() {
        let width = bounds.width > 0 ? bounds.width : currentWidth
        guard width > 0 else { return }

        recalculateIfNeeded(for: width, reportHeight: true)
        layoutCodeBlockButtons()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: lastMeasuredSize.width, height: lastMeasuredSize.height)
    }

    // MARK: - Appearance / theme

    #if os(macOS)
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        themeDidChangeIfNeeded()
    }
    #else
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            themeDidChangeIfNeeded()
            setNeedsDisplay()
            textView.setNeedsDisplay()
        }
    }
    #endif

    private func themeDidChangeIfNeeded() {
        let themeName = resolvedThemeName
        guard currentThemeName != themeName else { return }
        currentThemeName = themeName
        onThemeChange?(themeName)
    }

    var activeThemeName: String {
        currentThemeName ?? resolvedThemeName
    }

    private var resolvedThemeName: String {
        #if os(macOS)
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua: return codeTheme.dark
        default: return codeTheme.light
        }
        #else
        return traitCollection.userInterfaceStyle == .dark ? codeTheme.dark : codeTheme.light
        #endif
    }

    // MARK: - Public update API

    func showPlaceholder(text: String, fontSize: CGFloat, for request: MarkdownRenderRequest) {
        currentThemeName = request.themeName

        guard currentRequest != request || !isShowingPlaceholder else {
            recalculateIfNeeded(for: currentWidth, reportHeight: true)
            return
        }

        currentRequest = request
        currentDocument = nil
        isShowingPlaceholder = true
        display(document: .placeholder(text: text, fontSize: fontSize))
    }

    func apply(document: MarkdownRenderedDocument, for request: MarkdownRenderRequest, isStreamed: Bool = false) {
        currentThemeName = request.themeName

        guard currentRequest != request || isShowingPlaceholder || currentDocument == nil || isShowingStreamedContent else {
            recalculateIfNeeded(for: currentWidth, reportHeight: true)
            return
        }

        currentRequest = request
        currentDocument = document
        isShowingPlaceholder = false
        isShowingStreamedContent = isStreamed
        display(document: document)
    }

    func measuredSize(for width: CGFloat) -> CGSize {
        recalculateIfNeeded(for: width, reportHeight: false)
        return lastMeasuredSize
    }

    // MARK: - Rendering

    private func display(document: MarkdownRenderedDocument) {
        textView.update(document: document)
        syncCodeBlockButtons(with: document.codeBlocks)
        needsMeasurement = true
        #if os(macOS)
        needsLayout = true
        #else
        setNeedsLayout()
        #endif
        invalidateIntrinsicContentSize()
        recalculateIfNeeded(for: currentWidth, reportHeight: true)
    }

    private func recalculateIfNeeded(for width: CGFloat, reportHeight: Bool) {
        let resolvedWidth = ceil(width)
        guard resolvedWidth > 0 else { return }

        currentWidth = resolvedWidth

        guard needsMeasurement || lastMeasuredSize.width != resolvedWidth else {
            if reportHeight {
                reportHeightIfNeeded(lastMeasuredSize.height)
            }
            return
        }

        widthConstraint?.constant = resolvedWidth
        let measuredHeight = measureHeight()
        lastMeasuredSize = CGSize(width: resolvedWidth, height: measuredHeight)
        needsMeasurement = false

        if reportHeight {
            reportHeightIfNeeded(measuredHeight)
        }
    }

    private func measureHeight() -> CGFloat {
        guard currentWidth > 0 else { return 0 }

        textView.frame.size.width = currentWidth
        #if os(macOS)
        textView.markdownTextContainer.containerSize = CGSize(
            width: currentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        #else
        textView.markdownTextContainer.size = CGSize(
            width: currentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        #endif
        textView.markdownLayoutManager.ensureLayout(for: textView.markdownTextContainer)
        let usedRect = textView.markdownLayoutManager.usedRect(for: textView.markdownTextContainer)
        return ceil(usedRect.height)
    }

    private func reportHeightIfNeeded(_ measuredHeight: CGFloat) {
        guard measuredHeight > 0, measuredHeight != lastReportedHeight else { return }
        lastReportedHeight = measuredHeight
        onHeightChange?(measuredHeight)
    }

    // MARK: - Copy buttons

    #if os(macOS)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredCodeBlock(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredCodeBlockID = nil
        updateCopyButtonVisibility()
    }
    #endif

    private func syncCodeBlockButtons(with codeBlocks: [MarkdownCodeBlock]) {
        let nextIDs = Set(codeBlocks.map(\.id))

        for id in codeBlockButtons.keys where !nextIDs.contains(id) {
            codeBlockButtons[id]?.removeFromSuperview()
            codeBlockButtons[id] = nil
        }

        for codeBlock in codeBlocks where codeBlockButtons[codeBlock.id] == nil {
            let button = makeCopyButton(for: codeBlock.id)
            addSubview(button)
            codeBlockButtons[codeBlock.id] = button
        }
    }

    #if os(macOS)
    private func makeCopyButton(for id: Int) -> NSButton {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Copy code"
            ) ?? NSImage(),
            target: self,
            action: #selector(copyCodeBlock(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(String(id))
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        return button
    }
    #else
    private func makeCopyButton(for id: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        config.image = UIImage(systemName: "clipboard", withConfiguration: symbolConfig)
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config)
        button.tag = id
        button.addTarget(self, action: #selector(copyCodeBlockTouchUp(_:)), for: .touchUpInside)
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = true
        button.accessibilityLabel = "Copy code"
        return button
    }
    #endif

    private func layoutCodeBlockButtons() {
        cachedCodeBlockFrames = textView.codeBlockFrames()
        let codeBlockRects = Dictionary(
            uniqueKeysWithValues: cachedCodeBlockFrames.map { ($0.codeBlock.id, $0.frame) }
        )

        for (id, button) in codeBlockButtons {
            guard let codeBlockRect = codeBlockRects[id] else {
                button.isHidden = true
                continue
            }

            let convertedRect = textView.convert(codeBlockRect, to: self)
            button.frame = CGRect(
                x: convertedRect.maxX - Layout.copyButtonSize - Layout.copyButtonInset,
                y: convertedRect.maxY - Layout.copyButtonSize - Layout.copyButtonInset,
                width: Layout.copyButtonSize,
                height: Layout.copyButtonSize
            ).integral
            #if os(macOS)
            // visibility decided in updateCopyButtonVisibility based on hover
            #else
            button.isHidden = false
            #endif
        }

        #if os(macOS)
        updateCopyButtonVisibility()
        #endif
    }

    #if os(macOS)
    private func updateHoveredCodeBlock(for event: NSEvent) {
        let locationInTextView = textView.convert(event.locationInWindow, from: nil)
        var newHoveredID: Int?

        for (codeBlock, frame) in cachedCodeBlockFrames {
            if frame.contains(locationInTextView) {
                newHoveredID = codeBlock.id
                break
            }
        }

        guard hoveredCodeBlockID != newHoveredID else { return }
        hoveredCodeBlockID = newHoveredID
        updateCopyButtonVisibility()
    }

    private func updateCopyButtonVisibility() {
        for (id, button) in codeBlockButtons {
            button.isHidden = id != hoveredCodeBlockID
        }
    }

    @objc
    private func copyCodeBlock(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let codeBlockID = Int(identifier),
              let codeBlock = currentDocument?.codeBlocks.first(where: { $0.id == codeBlockID }) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeBlock.content, forType: .string)
    }
    #else
    @objc
    private func copyCodeBlockTouchUp(_ sender: UIButton) {
        guard let codeBlock = currentDocument?.codeBlocks.first(where: { $0.id == sender.tag }) else {
            return
        }
        UIPasteboard.general.string = codeBlock.content
    }
    #endif
}
