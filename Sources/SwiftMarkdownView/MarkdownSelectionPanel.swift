#if os(macOS)
import AppKit

/// Reuses one panel and its buttons across replies. Ordering it above the
/// chat window keeps the text view focused for typing and keyboard Copy.
@MainActor
final class MarkdownSelectionPanel: NSPanel {
    private struct Command: Equatable {
        let title: String
        let image: String
    }

    private static var shared: MarkdownSelectionPanel?
    private static var scheduledPreparation = false
    private weak var source: MarkdownPlainTextView?
    private let row = NSStackView()
    private var commands: [Command] = []
    private var rowSize = NSSize.zero
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        row.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        row.spacing = 4
        let glass = NSGlassEffectView()
        glass.cornerRadius = 14
        glass.contentView = row
        contentView = glass
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Prepare the first row after the reply is configured, ahead of mouse-up.
    static func prepare(with actions: [MarkdownSelectionAction]) {
        guard shared == nil, !scheduledPreparation else { return }
        scheduledPreparation = true
        DispatchQueue.main.async {
            guard shared == nil else { return }
            let panel = MarkdownSelectionPanel()
            panel.updateCommands(actions)
            shared = panel
        }
    }

    static func show(relativeTo rect: NSRect, in textView: MarkdownPlainTextView) {
        guard let window = textView.window, let screen = window.screen else { return }
        let panel = shared ?? MarkdownSelectionPanel()
        shared = panel
        panel.dismiss()
        panel.source = textView
        panel.updateCommands(textView.selectionActions)

        let anchor = window.convertToScreen(textView.convert(rect, to: nil))
        let visible = screen.visibleFrame
        let gap: CGFloat = 4
        let x = min(max(anchor.midX - panel.rowSize.width / 2, visible.minX), visible.maxX - panel.rowSize.width)
        let above = anchor.maxY + gap
        let y = above + panel.rowSize.height <= visible.maxY ? above : anchor.minY - gap - panel.rowSize.height
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panel.rowSize).integral, display: false)
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panel.watchForDismissal(in: window, clipView: textView.enclosingScrollView?.contentView)
    }

    static func dismiss(for textView: MarkdownPlainTextView) {
        guard let shared, shared.source === textView else { return }
        shared.dismiss()
    }

    private func updateCommands(_ actions: [MarkdownSelectionAction]) {
        let updated = [Command(title: String(localized: "Copy"), image: "square.on.square")]
            + actions.map { Command(title: $0.title, image: $0.systemImage) }
        guard commands != updated else { return }
        commands = updated
        for view in row.arrangedSubviews { view.removeFromSuperview() }
        for (index, command) in commands.enumerated() {
            let button = SelectionButton(title: command.title, target: self, action: #selector(performCommand(_:)))
            button.image = NSImage(systemSymbolName: command.image, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .accessoryBarAction
            button.tag = index
            row.addArrangedSubview(button)
        }
        rowSize = row.fittingSize
    }

    @objc private func performCommand(_ button: NSButton) {
        guard let source else { return }
        if button.tag == 0 {
            source.copy(button)
        } else {
            source.performSelectionAction(at: button.tag - 1)
        }
    }

    private func watchForDismissal(in window: NSWindow, clipView: NSClipView?) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                dismiss()
                return nil
            }
            if event.window !== self || event.type == .scrollWheel { dismiss() }
            return event
        }
        let center = NotificationCenter.default
        let dismiss: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main, using: dismiss))
        }
        if let clipView {
            clipView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main, using: dismiss))
        }
    }

    private func dismiss() {
        source = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        parent?.removeChildWindow(self)
        if isVisible { orderOut(nil) }
    }
}

private final class SelectionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
