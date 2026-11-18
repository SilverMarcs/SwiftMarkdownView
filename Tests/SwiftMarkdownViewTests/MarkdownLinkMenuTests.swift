#if os(macOS)
import AppKit
import Testing
@testable import SwiftMarkdownView

@Suite(.serialized)
@MainActor
struct MarkdownLinkMenuTests {
    @Test(arguments: [true, false])
    func selectedTextMenuKeepsNativeCommandsWithCopyAndQuoteFirst(quotingEnabled: Bool) throws {
        let (window, textView, event) = try transcript(link: nil)
        defer { window.close() }
        let selection = NSRange(location: 0, length: 8)
        textView.setSelectedRange(selection)
        var quotedText: String?
        if quotingEnabled {
            textView.selectionAction = MarkdownSelectionAction(title: "Quote", systemImage: "quote.opening") {
                quotedText = $0
            }
        }
        let parent = try #require(textView.superview)
        let parentMenu = NSMenu()
        parentMenu.addItem(withTitle: "Message Action", action: nil, keyEquivalent: "")
        parent.menu = parentMenu

        let menu = try #require(textView.menu(for: event))
        menu.update()

        let copy = try #require(menu.items.first)
        #expect(copy.action == #selector(NSText.copy(_:)))
        #expect(copy.isEnabled)
        #expect(menu.items.count { $0.action == #selector(NSText.copy(_:)) } == 1)
        #expect(menu.items.contains { $0.action == #selector(NSText.cut(_:)) })
        #expect(menu.items.contains { $0.title == "Message Action" })
        #expect(parentMenu.items.count == 1)
        #expect(!menu.allowsContextMenuPlugIns)
        #expect(parentMenu.allowsContextMenuPlugIns)
        #expect(textView.selectedRange() == selection)

        if quotingEnabled {
            let quote = try #require(menu.items.dropFirst().first)
            #expect(quote.title == "Quote")
            #expect(quote.isEnabled)
            let action = try #require(quote.action)
            #expect(NSApplication.shared.sendAction(action, to: quote.target, from: quote))
            #expect(quotedText == "download")
        } else {
            #expect(!menu.items.contains { $0.title == "Quote" })
        }
    }

    @Test
    func copyLinkStaysEnabledInReadOnlyTranscript() throws {
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }

        for destination in [
            "/Users/Zabir/Downloads/Relay-20261105-2358/Relay-0.2-universal-20261105.dmg",
            "file:///Users/example/Downloads/Relay.dmg",
            "https://example.com/download?version=2#mac",
            "Sources/App.swift:42"
        ] {
            let (window, textView, event) = try transcript(link: destination)
            defer { window.close() }
            let menu = try #require(textView.menu(for: event))
            let item = try #require(menu.items.first { $0.representedObject as? String == destination })
            #expect(menu.items.count { $0.action == item.action } == 1)
            let selection = textView.selectedRange()

            menu.update()

            #expect(item.isEnabled, "Copy Link should stay enabled for \(destination)")
            let action = try #require(item.action)
            #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
            #expect(pasteboard.string(forType: .string) == destination)
            #expect(textView.selectedRange() == selection)
        }
    }

    @Test
    func inheritedTextCommandsStillUseNativeValidation() throws {
        let (window, textView, _) = try transcript(link: "https://example.com")
        defer { window.close() }
        let menu = NSMenu()
        let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        cut.target = textView
        menu.addItem(cut)
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        menu.update()

        #expect(!cut.isEnabled, "A read-only transcript must not enable Cut")
    }

    private func transcript(link: String?) throws -> (NSWindow, MarkdownPlainTextView, NSEvent) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let textView = MarkdownPlainTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 180)
        textView.isEditable = false
        textView.isSelectable = true
        textView.markdownTextContainer.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        if let link { attributes[.link] = link }
        textView.markdownTextStorage.setAttributedString(NSAttributedString(string: "download the Relay installer", attributes: attributes))
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.markdownLayoutManager.ensureLayout(for: textView.markdownTextContainer)
        let glyph = textView.markdownLayoutManager.boundingRect(
            forGlyphRange: NSRange(location: 0, length: 1), in: textView.markdownTextContainer
        )
        let point = NSPoint(
            x: glyph.midX + textView.textContainerOrigin.x,
            y: glyph.midY + textView.textContainerOrigin.y
        )
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: textView.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        return (window, textView, event)
    }
}
#endif
