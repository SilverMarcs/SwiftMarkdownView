#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import SwiftMarkdownView

@MainActor
struct MarkdownSelectionActionTests {
    @Test
    func actionsAreOfferedInTheOrderTheModifiersAreWritten() {
        let view = SelectionActionsProbe()
            .markdownSelectionAction("Quote", systemImage: "quote.opening") { _ in }
            .markdownSelectionAction("Hidden", systemImage: "eye.slash", isEnabled: false) { _ in }
            .markdownSelectionAction("Scratchpad", systemImage: "note.text") { _ in }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        #expect(SelectionActionsProbe.titles == ["Quote", "Scratchpad"])
    }
}

private struct SelectionActionsProbe: View {
    @MainActor static var titles: [String] = []
    @Environment(\.markdownSelectionActions) private var actions

    var body: some View {
        Self.titles = actions.map(\.title)
        return Color.clear
    }
}
#endif
