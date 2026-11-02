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
        let helpItems = menu.item(withTitle: "Help")?.submenu?.items ?? []
        #expect(helpItems.contains { $0.title == "Zipboy Help" && $0.keyEquivalent == "?" })

        // Third-launch default handler offer triggers exactly once on launch 3.
        #expect(!settings.recordLaunchAndShouldOfferDefaultHandler())
        #expect(!settings.recordLaunchAndShouldOfferDefaultHandler())
        #expect(settings.recordLaunchAndShouldOfferDefaultHandler())
        #expect(!settings.recordLaunchAndShouldOfferDefaultHandler())
    }

    @Test func helpWindowFiltersTopicsAndFindsPasswordSection() {
        let help = HelpWindowController.shared
        help.filter("")
        #expect(help.visibleSections.count == HelpWindowController.allSections.count)

        help.filter("password")
        #expect(help.visibleSections.count == 1)
        #expect(help.visibleSections.first?.title == "Passwords & AES-256 Encryption")

        help.filter("verify")
        #expect(help.visibleSections.first?.title == "Integrity Verification & Checksums")

        help.filter("")
        #expect(help.visibleSections.count == HelpWindowController.allSections.count)
    }

    @Test func keychainStoresRetrievesAndDeletesPasswords() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "keychain-test-\(UUID().uuidString).zip")
        try Data("zip".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let service = "com.oddurs.zipboy.tests.\(UUID().uuidString)"
        defer { Keychain.deletePassword(for: tempFile, service: service) }

        #expect(Keychain.password(for: tempFile, service: service) == nil)
        #expect(Keychain.setPassword("s3cr3t!", for: tempFile, service: service))
        #expect(Keychain.password(for: tempFile, service: service) == "s3cr3t!")

        Keychain.deletePassword(for: tempFile, service: service)
        #expect(Keychain.password(for: tempFile, service: service) == nil)
    }

    @Test func springLoadingExpandsCollapsedFolderAfterHover() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "spring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("FolderA/Sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("FolderA/Sub/a.txt"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("top.txt"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add(
            [dir.appendingPathComponent("FolderA"), dir.appendingPathComponent("top.txt")],
            into: ""
        ) { _ in .keepBoth }

        let browser = BrowserViewController()
        browser.document = doc
        browser.springLoadDelay = 0.05
        browser.reload()

        let folderNode = try #require(browser.outline.item(atRow: 0) as? Node)
        #expect(folderNode.path == "FolderA")
        #expect(!browser.outline.isItemExpanded(folderNode))

        browser.scheduleSpringLoad(for: folderNode)
        try await Task.sleep(for: .milliseconds(120))
        #expect(browser.outline.isItemExpanded(folderNode))
    }
}
