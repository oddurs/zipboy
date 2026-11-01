import AppKit
import Testing
import ZipboyKit

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

    @Test func rowsFollowSystemSelectionStyle() {
        let row = ArchiveRowView()
        #expect(Theme.accent == .controlAccentColor)
        #expect(row.interiorBackgroundStyle == .normal)
        row.isSelected = true
        row.isEmphasized = true
        #expect(row.interiorBackgroundStyle == .emphasized)
        row.isSelected = false
        #expect(row.interiorBackgroundStyle == .normal)
    }

    @Test func settingsWindowReflectsAndRestoresDefaults() {
        let suiteName = "com.oddurs.zipboy.looktests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = Settings(defaults: defaults)
        let controller = SettingsWindowController(settings: settings)
        #expect(controller.launchPopup.indexOfSelectedItem == 0)
        #expect(controller.foldersFirstCheckbox.state == .on)
        #expect(controller.autoExpandCheckbox.state == .on)
        #expect(controller.showHiddenCheckbox.state == .off)
        #expect(controller.destinationPopup.indexOfSelectedItem == 0)
        #expect(controller.wrapPopup.indexOfSelectedItem == 0)
        #expect(controller.revealCheckbox.state == .on)
        #expect(controller.compressionControl.selectedSegment == 1)

        settings.launchBehavior = .doNothing
        settings.keepFoldersOnTop = false
        settings.showHiddenFiles = true
        settings.extractDestination = .downloads
        settings.wrapExtractedFiles = .never
        settings.compressionLevel = .best

        #expect(controller.launchPopup.indexOfSelectedItem == 1)
        #expect(controller.foldersFirstCheckbox.state == .off)
        #expect(controller.showHiddenCheckbox.state == .on)
        #expect(controller.destinationPopup.indexOfSelectedItem == 1)
        #expect(controller.wrapPopup.indexOfSelectedItem == 2)
        #expect(controller.compressionControl.selectedSegment == 2)

        controller.restoreDefaults(nil)
        #expect(controller.launchPopup.indexOfSelectedItem == 0)
        #expect(controller.foldersFirstCheckbox.state == .on)
        #expect(controller.showHiddenCheckbox.state == .off)
        #expect(controller.destinationPopup.indexOfSelectedItem == 0)
        #expect(controller.wrapPopup.indexOfSelectedItem == 0)
        #expect(controller.compressionControl.selectedSegment == 1)

        let menu = MainMenu.make()
        let appItems = menu.items.first?.submenu?.items ?? []
        #expect(appItems.contains { $0.title == "Settings…" && $0.keyEquivalent == "," })
        let viewItems = menu.item(withTitle: "View")?.submenu?.items ?? []
        #expect(viewItems.contains { $0.title == "Show Hidden Files" && $0.keyEquivalent == "." })
    }
}
