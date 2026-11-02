import AppKit
import Testing
import ZipboyKit

@testable import Zipboy

/// What VoiceOver can reach in each window, checked for a name on everything it would announce.
@MainActor
@Suite(.serialized) struct AccessibilityTests {
    /// Everything visible and announced in `view`, with what VoiceOver would call it.
    func announced(in view: NSView) -> [(NSView, String?)] {
        guard !view.isHiddenOrHasHiddenAncestor else { return [] }
        var found: [(NSView, String?)] = []
        let isControl = view is NSButton || view is NSPopUpButton || view is NSSegmentedControl
        let isPicture = view is NSImageView || view.accessibilityRole() == .image
        // A control is always reached (its cell answers for it); a picture only when it isn't decoration.
        if isControl || (isPicture && view.isAccessibilityElement()) {
            let button = view as? NSButton
            // A pop-up's title is its current choice and a segmented control's are its segments; neither
            // says what is being chosen, so they need a label of their own.
            let choice = view is NSPopUpButton || view is NSSegmentedControl
            let name =
                choice
                ? view.accessibilityLabel().flatMap { $0.isEmpty ? nil : $0 }
                : [
                    view.accessibilityLabel(), view.accessibilityTitle(), button?.title,
                    button?.image?.accessibilityDescription,
                ].compactMap { $0 }.first { !$0.isEmpty }
            found.append((view, name))
        }
        for child in view.subviews { found += announced(in: child) }
        return found
    }

    func expectNamed(_ window: NSWindow?, _ place: String) throws {
        let content = try #require(window?.contentView)
        content.layoutSubtreeIfNeeded()
        let reached = announced(in: content)
        // An audit that finds nothing proves nothing.
        #expect(!reached.isEmpty, "\(place): nothing announced was found")
        for (view, name) in reached {
            #expect(name != nil, "\(place): an unnamed \(type(of: view)) at \(view.frame)")
        }
        // Spaces and separators are layout, which VoiceOver passes over.
        let layout: Set<NSToolbarItem.Identifier> = [.flexibleSpace, .space, .inspectorTrackingSeparator]
        for item in window?.toolbar?.items ?? [] where !layout.contains(item.itemIdentifier) {
            #expect(!item.label.isEmpty || item is NSSearchToolbarItem, "\(place): toolbar item \(item.itemIdentifier)")
        }
    }

    @Test func everyWindowNamesWhatVoiceOverReaches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        let empty = ArchiveDocument()
        empty.makeWindowControllers()
        defer { empty.close() }
        try expectNamed(empty.windowControllers.first?.window, "empty archive")

        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([dir.appendingPathComponent("notes.txt")], into: "") { _ in .keepBoth }
        let controller = try #require(doc.windowControllers.first as? ArchiveWindowController)
        controller.browser.outline.selectRowIndexes([0], byExtendingSelection: false)
        try expectNamed(controller.window, "archive with a file selected")

        try expectNamed(AboutWindowController().window, "About")
        try expectNamed(WelcomeWindowController().window, "Welcome")
        try expectNamed(
            SettingsWindowController(settings: Settings(defaults: UserDefaults(suiteName: "ax-\(UUID())")!)).window,
            "Settings")
    }

    @Test func listRowsReadTheirNameKindAndSize() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(count: 2048).write(to: dir.appendingPathComponent("report.txt"))
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        try await doc.add([dir.appendingPathComponent("report.txt")], into: "") { _ in .keepBoth }
        let outline = try #require(doc.windowControllers.first as? ArchiveWindowController).browser.outline
        let cells = (0..<outline.numberOfColumns).compactMap {
            (outline.view(atColumn: $0, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
        }
        #expect(cells.contains("report.txt"))
        #expect(cells.contains { $0.contains("KB") })
        #expect(cells.contains { $0.localizedCaseInsensitiveContains("text") })
    }

    @Test func addsDeletesAndSavesAreAnnounced() async throws {
        var heard: [String] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("say-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt"] { try Data(name.utf8).write(to: dir.appendingPathComponent(name)) }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        doc.announce = { heard.append($0) }
        try await doc.add(["a.txt", "b.txt"].map { dir.appendingPathComponent($0) }, into: "") { _ in .keepBoth }
        try doc.remove(["a.txt"])
        #expect(heard == ["Added 2 items", "Deleted “a.txt”"])

        let saved = dir.appendingPathComponent("Saved.zip")
        try await doc.save(to: saved, ofType: ArchiveDocument.zipType, for: .saveAsOperation)
        #expect(heard.last?.hasPrefix("Saved") == true)
    }
}
