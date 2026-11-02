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
        #expect(view.chooseButton.prominent)

        view.mode = .loading(0.42)
        #expect(view.accessibilityLabel()?.contains("Unzipping") == true)
        let zipper = view.subviews.flatMap(\.subviews).compactMap { $0 as? ZipperProgressView }.first
        #expect(zipper?.accessibilityRole() == .progressIndicator)
        #expect(zipper?.accessibilityValue() as? String == "42 percent")

        view.mode = .noResults
        #expect(view.accessibilityLabel()?.contains("No matches") == true)
    }

    /// WCAG contrast between `text` drawn over `fill` over `ground`, in one appearance.
    func contrast(_ text: NSColor, on fill: NSColor?, over ground: NSColor, _ name: NSAppearance.Name) -> Double {
        var result = 0.0
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            func rgba(_ color: NSColor) -> [Double] {
                let c = color.usingColorSpace(.sRGB)!
                return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init)
            }
            func over(_ top: [Double], _ bottom: [Double]) -> [Double] {
                (0..<3).map { top[$0] * top[3] + bottom[$0] * (1 - top[3]) } + [1]
            }
            func luminance(_ c: [Double]) -> Double {
                let lin = c.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
            }
            var back = rgba(ground)
            if let fill { back = over(rgba(fill), back) }
            let front = over(rgba(text), back)
            let (a, b) = (luminance(front), luminance(back))
            result = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        return result
    }

    @Test func selectedRowsKeepTheirTextReadable() {
        for look in [NSAppearance.Name.aqua, .darkAqua] {
            let text = contrast(.labelColor, on: Theme.selection, over: .controlBackgroundColor, look)
            #expect(text >= 4.5, "\(look.rawValue): \(text)")
        }
        // Secondary text would fall under 4.5:1 on the tint, so a selected row draws it as primary.
        let row = ArchiveRowView()
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("size")
        cell.textField = NSTextField(labelWithString: "1 KB")
        cell.addSubview(cell.textField!)
        row.addSubview(cell)
        row.isSelected = true
        #expect(cell.textField?.textColor == .labelColor)
        row.isSelected = false
        #expect(cell.textField?.textColor == .secondaryLabelColor)
        #expect(row.interiorBackgroundStyle == .normal)
    }

    @Test func inkReadsOnNeonAndTheAccentReadsOnTheWindow() {
        for look in [NSAppearance.Name.aqua, .darkAqua] {
            let ink = contrast(Theme.ink, on: Theme.neon, over: .windowBackgroundColor, look)
            #expect(ink >= 4.5, "ink on neon, \(look.rawValue): \(ink)")
            // Strokes and glyphs are non-text, so 3:1.
            let accent = contrast(Theme.accent, on: nil, over: .windowBackgroundColor, look)
            #expect(accent >= 3, "accent, \(look.rawValue): \(accent)")
        }
    }

    @Test func theAccentFollowsOnlyWhenThePersonHasNotChosenOne() {
        let multicolor = Theme.accentDefaults(over: [:])
        #expect(multicolor["AppleAccentColor"] as? Int == Theme.systemGreen)
        #expect(multicolor["AppleHighlightColor"] != nil)

        #expect(Theme.accentDefaults(over: ["AppleAccentColor": 4]).isEmpty)

        let ownHighlight = Theme.accentDefaults(over: ["AppleHighlightColor": "1 1 0 Yellow"])
        #expect(ownHighlight["AppleAccentColor"] as? Int == Theme.systemGreen)
        #expect(ownHighlight["AppleHighlightColor"] == nil)
    }

    @Test func infoTableRowsShareTheirEdges() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        let table = InfoTable()
        host.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            table.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        table.show([
            ("Size", "1 KB"),
            nil,
            ("Where", "Top level"),
            ("SHA-256", String(repeating: "ab", count: 32)),
            ("Modified", "Nov 1, 2026 at 8:05 PM"),
        ])
        host.layoutSubtreeIfNeeded()
        #expect(table.rows.count == 4)
        for row in table.rows {
            let frame = row.convert(row.bounds, to: host)
            #expect(frame.minX == 0)
            #expect(frame.maxX == 280)
        }
    }

    @Test func theInspectorOffersOneProminentAction() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("inspect-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([file], into: "") { _ in .keepBoth }
        let inspector = PreviewViewController()
        inspector.show([], archive: doc)
        #expect(inspector.primary.prominent)
        #expect(!inspector.secondary.prominent)
        #expect(inspector.primary.accessibilityLabel() == "Extract All")
    }

    @Test func theProminentButtonGoesQuietInABackgroundWindow() {
        let alone = ActionButton("Extract", action: nil, prominent: true)
        #expect(alone.isLit)
        #expect(!ActionButton("Verify", action: nil, prominent: false).isLit)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: true)
        window.contentView?.addSubview(alone)
        #expect(!window.isMainWindow)
        #expect(!alone.isLit)
    }

    @Test func theInspectorToggleSaysWhatItWillDo() throws {
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        let split = try #require(
            doc.windowControllers.first?.window?.contentViewController as? InspectorSplitViewController)
        let item = NSMenuItem(
            title: "", action: #selector(NSSplitViewController.toggleInspector(_:)), keyEquivalent: "")
        let inspector = try #require(split.splitViewItems.last)
        // The split view autosaves whether it's collapsed, so leave it open as the next window expects.
        defer { inspector.isCollapsed = false }
        inspector.isCollapsed = false
        _ = split.validateUserInterfaceItem(item)
        #expect(item.title == "Hide Inspector")
        inspector.isCollapsed = true
        _ = split.validateUserInterfaceItem(item)
        #expect(item.title == "Show Inspector")
    }

    @Test func theInspectorHeadingSaysEachThingOnce() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("heading-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([file], into: "") { _ in .keepBoth }
        let inspector = PreviewViewController()

        inspector.show([], archive: doc)
        #expect(inspector.subtitle.stringValue == "ZIP archive")
        let labels = inspector.table.rows.compactMap { $0.accessibilityLabel() }
        #expect(!labels.contains { $0.hasPrefix("Format:") })

        let node = try #require(doc.tree?.children.first)
        inspector.show([node], archive: doc)
        #expect(inspector.subtitle.stringValue == node.kind)
        #expect(inspector.table.rows.contains { $0.accessibilityLabel()?.hasPrefix("Size:") == true })
    }

    @Test func contextMenuCommandsCarryTheirSymbols() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menu-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([file], into: "") { _ in .keepBoth }
        let browser = BrowserViewController()
        browser.document = doc
        browser.reload()
        let menu = try #require(browser.outline.menu)

        for selected in [IndexSet(), IndexSet(integer: 0)] {
            browser.outline.selectRowIndexes(selected, byExtendingSelection: false)
            browser.menuNeedsUpdate(menu)
            let commands = menu.items.filter { !$0.isSeparatorItem }
            #expect(!commands.isEmpty)
            for item in commands { #expect(item.image != nil, "\(item.title) has no symbol") }
        }
    }

    @Test func endingASearchPutsBackTheFoldersThatWereOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("FolderA/Sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("FolderA/Sub/a.txt"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("top.txt"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([dir.appendingPathComponent("FolderA"), dir.appendingPathComponent("top.txt")], into: "") {
            _ in .keepBoth
        }
        let browser = BrowserViewController()
        browser.document = doc
        browser.reload()
        // The list shows its own copy of the tree, so rows are found through the outline.
        func row(_ path: String) -> Node? {
            (0..<browser.outline.numberOfRows).lazy.compactMap { browser.outline.item(atRow: $0) as? Node }
                .first { $0.path == path }
        }
        browser.outline.expandItem(try #require(row("FolderA")) as Node)

        browser.filter("nothing matches this")
        browser.filter("")
        let folder: Node = try #require(row("FolderA"))
        let sub: Node = try #require(row("FolderA/Sub"))
        #expect(browser.outline.isItemExpanded(folder))
        #expect(!browser.outline.isItemExpanded(sub))

        // What was found and selected stays selected, with its folders opened to show it.
        browser.filter("a.txt")
        let match = try #require(row("FolderA/Sub/a.txt"))
        let found = browser.outline.row(forItem: match)
        browser.outline.selectRowIndexes([found], byExtendingSelection: false)
        browser.filter("")
        #expect(browser.selection.map(\.path) == ["FolderA/Sub/a.txt"])
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
        try Keychain.setPassword("s3cr3t!", for: tempFile, service: service)
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
