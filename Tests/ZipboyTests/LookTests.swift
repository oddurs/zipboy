import AppKit
import Testing

@testable import Zipboy

/// The parts of the look that aren't just pixels: motion that respects Reduce Motion, and what
/// VoiceOver hears.
@MainActor
@Suite(.serialized) struct LookTests {
    func tray() -> EmptyStateView {
        let view = EmptyStateView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func traysMarchOnlyWhenMotionIsAllowed() {
        defer { Theme.reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } }

        Theme.reduceMotion = { false }
        let moving = tray()
        moving.highlighted = true
        #expect(moving.isAnimating)
        moving.highlighted = false
        #expect(!moving.isAnimating)

        Theme.reduceMotion = { true }
        let still = tray()
        still.highlighted = true
        #expect(!still.isAnimating)
    }

    @Test func voiceOverHearsEachState() {
        let view = tray()
        #expect(view.accessibilityRole() == .group)
        #expect(view.accessibilityLabel()?.contains("Drop files here") == true)
        #expect(view.chooseButton.accessibilityLabel() == "Choose files to add")

        view.mode = .loading(0.42)
        #expect(view.accessibilityLabel()?.contains("Unzipping") == true)
        let zipper = view.subviews.flatMap(\.subviews).compactMap { $0 as? ZipperProgressView }.first
        #expect(zipper?.accessibilityRole() == .progressIndicator)
        #expect(zipper?.accessibilityValue() as? String == "42 percent")

        view.mode = .noResults
        #expect(view.accessibilityLabel()?.contains("No matches") == true)
    }

    @Test func selectedRowsKeepTheirTextReadable() {
        let row = ArchiveRowView()
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("size")
        let field = NSTextField(labelWithString: "9 KB")
        cell.textField = field
        cell.addSubview(field)
        row.addSubview(cell)
        #expect(row.interiorBackgroundStyle == .normal)
        row.isSelected = true
        #expect(field.textColor == .labelColor)
        row.isSelected = false
        #expect(field.textColor == .secondaryLabelColor)
    }
}
