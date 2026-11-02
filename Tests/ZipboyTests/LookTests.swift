import AppKit
import Testing
import ZipboyKit

@testable import Zipboy

/// The parts of the look and feel that aren't just pixels: what VoiceOver hears, what lights during a
/// drag, and how the list answers the keyboard and mouse.
@MainActor
@Suite(.serialized) struct LookTests {
    func tray() -> EmptyStateView {
        let view = EmptyStateView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func theDropAreaLightsInTheAccentOnlyWhileADropWaits() {
        let view = tray()
        let rest = view.outlineColor
        view.highlighted = true
        var accent: CGColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { accent = NSColor.controlAccentColor.cgColor }
        #expect(view.outlineColor == accent)
        view.highlighted = false
        #expect(view.outlineColor == rest)

        // Searching or loading isn't somewhere to drop, so nothing lights.
        view.mode = .noResults("x")
        view.highlighted = true
        #expect(view.outlineColor == rest)
    }

    @Test func voiceOverHearsEachState() {
        let view = tray()
        #expect(view.accessibilityRole() == .group)
        #expect(view.accessibilityLabel()?.contains("Drop Files Here") == true)
        #expect(view.chooseButton.accessibilityLabel() == "Choose files to add")
        #expect(view.chooseButton.isProminent)

        view.mode = .loading(0.42)
        #expect(view.accessibilityLabel()?.contains("Unzipping") == true)
        let bar = view.subviews.flatMap(\.subviews).compactMap { $0 as? NSProgressIndicator }.first
        #expect(bar?.doubleValue == 0.42)
        #expect(bar?.accessibilityValue() as? String == "42 percent")

        view.mode = .noResults("tax")
        #expect(view.accessibilityLabel()?.contains("No Results for “tax”") == true)
    }

    @Test func theListDrawsTheSystemSelection() async throws {
        let (doc, browser, _) = try await browsing(["one.txt"])
        defer { doc.close() }
        browser.outline.selectRowIndexes([0], byExtendingSelection: false)
        let row = try #require(browser.outline.rowView(atRow: 0, makeIfNecessary: true))
        #expect(type(of: row) == NSTableRowView.self)
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
        #expect(inspector.primary.isProminent)
        #expect(!inspector.secondary.isProminent)
        #expect(inspector.primary.title == "Extract All")
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
        // Waits for the folder to open rather than a fixed time: another suite can hold the main thread
        // for seconds, and a fixed sleep then loses the race and fails for nothing.
        let deadline = ContinuousClock.now + .seconds(5)
        while !browser.outline.isItemExpanded(folderNode), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(browser.outline.isItemExpanded(folderNode))
    }

    /// An archive holding `names` as small files at its top level, shown in a list inside a window.
    func browsing(_ names: [String]) async throws -> (ArchiveDocument, BrowserViewController, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names { try Data(name.utf8).write(to: dir.appendingPathComponent(name)) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        try await doc.add(names.map { dir.appendingPathComponent($0) }, into: "") { _ in .keepBoth }
        let browser = BrowserViewController()
        browser.document = doc
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered,
            defer: true)
        window.contentView = browser.view
        // As the window controller does, so edits reach this list rather than the window's own.
        doc.onChange = { browser.reload() }
        browser.reload()
        return (doc, browser, dir)
    }

    @Test func typingANameFindsItsRow() async throws {
        let (doc, browser, _) = try await browsing(["alpha.txt", "beta.txt"])
        defer { doc.close() }
        let outline = browser.outline
        let node = try #require(outline.item(atRow: 1) as? Node)
        #expect(browser.outlineView(outline, typeSelectStringFor: outline.tableColumns[0], item: node) == "beta.txt")
        #expect(browser.outlineView(outline, typeSelectStringFor: outline.tableColumns[3], item: node) == nil)
    }

    @Test func escapeCancelsARename() async throws {
        let (doc, browser, _) = try await browsing(["keep.txt"])
        defer { doc.close() }
        let cell = try #require(browser.outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let field = try #require(cell.textField)
        field.stringValue = "half typed"
        let handled = browser.control(
            field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(handled)
        #expect(field.stringValue == "keep.txt")
        #expect(doc.tree?.children.map(\.name) == ["keep.txt"])
        // Other commands, such as Return, still go to the field.
        #expect(!browser.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    @Test func rightClickingBlankSpaceIsAboutTheArchive() async throws {
        let (doc, browser, _) = try await browsing(["a.txt"])
        defer { doc.close() }
        let menu = NSMenu()
        browser.outline.selectRowIndexes([0], byExtendingSelection: false)
        browser.fillContextMenu(menu, onBlank: false)
        #expect(menu.items.contains { $0.title == "Rename" })

        browser.fillContextMenu(menu, onBlank: true)
        #expect(browser.selection.isEmpty)
        #expect(menu.items.contains { $0.title == "Add Files…" })
        #expect(!menu.items.contains { $0.title == "Rename" })
    }

    @Test func addedItemsAreShownWhereTheyLanded() async throws {
        let (doc, browser, dir) = try await browsing(["same.txt"])
        defer { doc.close() }
        // The second copy is renamed to keep both, and it's that name that comes back.
        let added = try await doc.add([dir.appendingPathComponent("same.txt")], into: "") { _ in .keepBoth }
        #expect(added.count == 1)
        #expect(added != ["same.txt"])
        #expect(doc.tree?.find(added[0]) != nil)

        let extra = dir.appendingPathComponent("extra.txt")
        try Data("e".utf8).write(to: extra)
        await browser.add([extra], into: "")?.value
        #expect(browser.selection.map(\.path) == ["extra.txt"])
    }

    @Test func aDropLightsTheListOnlyWhenItWouldBeAccepted() async throws {
        let (doc, browser, dir) = try await browsing(["top.txt"])
        defer { doc.close() }
        let outline = browser.outline

        let outside = FakeDrag(files: [dir.appendingPathComponent("top.txt")], source: nil)
        #expect(browser.outlineView(outline, validateDrop: outside, proposedItem: nil, proposedChildIndex: -1) == .copy)
        #expect(outline.rootDropGlow)

        // Moving a top-level item to the top level goes nowhere, so nothing lights.
        browser.dragged = ["top.txt"]
        let inside = FakeDrag(files: [dir.appendingPathComponent("top.txt")], source: outline)
        #expect(browser.outlineView(outline, validateDrop: inside, proposedItem: nil, proposedChildIndex: -1) == [])
        #expect(!outline.rootDropGlow)
    }

    @Test func theInspectorTakesFilesFromOutsideOnly() {
        let view = FileDropView()
        var hovering = false
        var dropped: [URL] = []
        view.onHover = { hovering = $0 }
        view.onDrop = { dropped = $0 }
        let file = URL(fileURLWithPath: "/tmp/dropped.txt")

        let outside = FakeDrag(files: [file], source: nil)
        #expect(view.draggingEntered(outside) == .copy)
        #expect(hovering)
        #expect(view.performDragOperation(outside))
        #expect(dropped == [file])
        view.draggingExited(outside)
        #expect(!hovering)

        let fromList = FakeDrag(files: [file], source: NSOutlineView())
        #expect(view.draggingEntered(fromList) == [])
        #expect(!hovering)
    }
}

/// A drag carrying file URLs, for exercising drop handling without a mouse.
@MainActor
final class FakeDrag: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard = NSPasteboard(name: .init("zipboy-tests-\(UUID().uuidString)"))
    let draggingSource: Any?

    init(files: [URL], source: Any?) {
        draggingSource = source
        super.init()
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects(files.map { $0 as NSURL })
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

/// Every prompt can be dismissed from the keyboard, as every Mac sheet can.
@MainActor
struct PromptKeyboardTests {
    func escapes(_ alert: NSAlert) -> [String] {
        alert.buttons.filter { $0.keyEquivalent == "\u{1b}" }.map(\.title)
    }

    @Test func everyPromptCancelsWithEscape() {
        #expect(escapes(Prompts.passwordAlert(for: "a.zip", retry: false).0) == ["Cancel"])
        #expect(escapes(Prompts.newPasswordAlert(mismatch: true).0) == ["Cancel"])
        #expect(escapes(Prompts.discardAlert(toReadNamesAs: TextEncoding.allCases[0])) == ["Cancel"])
        #expect(escapes(Prompts.Conflicts.alert(for: "a.txt", more: true)) == ["Stop"])
    }
}

@MainActor
struct AboutTests {
    @Test func aboutCreditsLibarchiveAndLinksTheProject() {
        let credits = AppDelegate.credits
        #expect(credits.string.contains("libarchive"))
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { links.append(url) }
        }
        #expect(
            links.map(\.absoluteString) == [
                "https://github.com/oddurs/zipboy", "https://github.com/oddurs/zipboy/issues",
            ])

        // The menu registers the Services and Help menus with NSApp, which must exist first.
        _ = NSApplication.shared
        let about = MainMenu.make().items.first?.submenu?.items.first
        #expect(about?.title == "About Zipboy")
        #expect(about?.action == #selector(AppDelegate.showAbout(_:)))
    }
}

@MainActor
struct DockMenuTests {
    @Test func theDockMenuStartsAndOpensArchives() throws {
        let menu = try #require(AppDelegate().applicationDockMenu(NSApplication.shared))
        #expect(menu.items.map(\.title) == ["New Archive", "Open…"])
        let new = menu.items[0]
        #expect(new.target === NSDocumentController.shared)
        #expect(new.action == #selector(NSDocumentController.newDocument(_:)))
        #expect(menu.items[1].action == #selector(NSDocumentController.openDocument(_:)))

        // The same command as the File menu's, so the two can't drift apart.
        let file = MainMenu.make().item(withTitle: "File")?.submenu
        #expect(file?.item(withTitle: "New Archive")?.action == new.action)
    }
}

@MainActor
@Suite(.serialized) struct RestorationTests {
    func archive() async throws -> ArchiveDocument {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("FolderA/Sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("FolderA/Sub/a.txt"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("top.txt"))
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        try await doc.add([dir.appendingPathComponent("FolderA"), dir.appendingPathComponent("top.txt")], into: "") {
            _ in .keepBoth
        }
        return doc
    }

    func controller(_ doc: ArchiveDocument) throws -> ArchiveWindowController {
        try #require(doc.windowControllers.first as? ArchiveWindowController)
    }

    @Test func aWindowComesBackWithItsFoldersAndSelection() async throws {
        let before = try await archive()
        defer { before.close() }
        let first = try controller(before)
        let outline = first.browser.outline
        outline.expandItem(try #require(outline.item(atRow: 0) as? Node))
        first.browser.restore(.init(expanded: ["FolderA"], selected: ["FolderA/Sub"], query: ""))
        #expect(first.browser.savedState == .init(expanded: ["FolderA"], selected: ["FolderA/Sub"], query: ""))

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        first.window(try #require(first.window), willEncodeRestorableState: archiver)
        archiver.finishEncoding()

        let after = try await archive()
        defer { after.close() }
        let second = try controller(after)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        second.window(try #require(second.window), didDecodeRestorableState: unarchiver)
        #expect(second.browser.savedState.selected == ["FolderA/Sub"])
        #expect(second.browser.savedState.expanded == ["FolderA"])
    }

    @Test func stateWaitsForTheArchiveToOpenAndSkipsWhatIsGone() async throws {
        let browser = BrowserViewController()
        browser.restore(.init(expanded: ["FolderA", "Missing"], selected: ["top.txt", "gone.txt"], query: ""))
        // Nothing to apply it to yet; the first load after opening does.
        let doc = try await archive()
        defer { doc.close() }
        browser.document = doc
        browser.reload()
        #expect(browser.savedState.selected == ["top.txt"])
        #expect(browser.savedState.expanded == ["FolderA"])
    }

    @Test func archivesOpenAsTabsWhenThePersonPrefersThem() async throws {
        let doc = try await archive()
        defer { doc.close() }
        #expect(try controller(doc).window?.tabbingMode == .automatic)
    }
}
