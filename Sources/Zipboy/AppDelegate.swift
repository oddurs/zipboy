import AppKit
import UniformTypeIdentifiers
import ZipboyKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register sensible defaults before any window or document opens.
        _ = Settings.shared
        // The first controller made becomes the shared one.
        _ = DocumentController()
        // Workspaces outlive the app only when it crashed, so whatever is there now is abandoned.
        Workspace.removeAbandoned()
        NSApp.servicesProvider = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Dock icon, About, and alerts follow Dark Mode, switching as the appearance does.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { app.applicationIconImage = Mugi.appIcon(for: app.effectiveAppearance) }
        }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            NSClassFromString("XCTestCase") == nil
        else { return }
        // Every launch counts toward the third, when Zipboy offers once to open ZIPs; the welcome only
        // keeps the two from landing on the same launch.
        // Past the test guard, so a test run never reaches for the network.
        Updater.shared.checkIfDue()
        let offer = Settings.shared.recordLaunchAndShouldOfferDefaultHandler()
        if Settings.shared.shouldShowWelcomeOnce() {
            // After the first window, so the welcome sits in front of it.
            DispatchQueue.main.async { WelcomeWindowController.shared.present() }
        } else if offer {
            offerDefaultZipHandler()
        }
    }

    private var appearanceObservation: NSKeyValueObservation?

    @objc func showWelcome(_ sender: Any?) {
        WelcomeWindowController.shared.present()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }

    /// The Dock lists the open windows itself; this adds what a document app's Dock menu offers.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "New Archive", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "")
        for item in menu.items { item.target = NSDocumentController.shared }
        return menu
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.shared.showWindow(sender)
        AboutWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }

    /// What the About panel says beneath the version: what Zipboy is built on, and where to find it.
    static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered,
        ]
        func link(_ title: String, _ url: String) -> NSAttributedString {
            var attributes = plain
            attributes[.link] = URL(string: url)
            return NSAttributedString(string: title, attributes: attributes)
        }
        let text = NSMutableAttributedString(
            string: "Reads and writes archives with libarchive, which ships with macOS.\n", attributes: plain)
        text.append(link("Source Code", "https://github.com/oddurs/zipboy"))
        text.append(NSAttributedString(string: "  ·  ", attributes: plain))
        text.append(link("Report an Issue", "https://github.com/oddurs/zipboy/issues"))
        return text
    }

    /// Help Viewer, with Zipboy's book, when the book is there and registers; otherwise the help window,
    /// as in a test run or a debug build without the book.
    @objc func showHelp(_ sender: Any?) {
        if Bundle.main.url(forResource: "Zipboy", withExtension: "help") != nil,
            NSHelpManager.shared.registerBooks(in: .main)
        {
            NSApp.showHelp(sender)
            return
        }
        HelpWindowController.shared.showWindow(sender)
        HelpWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }

    private func offerDefaultZipHandler() {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { return }
        if let current = NSWorkspace.shared.urlForApplication(toOpen: .zip),
            current.standardizedFileURL == appURL.standardizedFileURL
        {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open ZIP archives with Zipboy by default?"
        alert.informativeText =
            "Double-clicking a .zip file in the Finder will open it in Zipboy instead of Archive Utility. You can change this anytime in Settings."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: .zip) { _ in }
        }
    }

    // MARK: Finder Services

    @objc func compressWithZipboy(
        _ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls =
            pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        runService { [try Self.compressFiles(urls)] }
    }

    @objc func extractWithZipboy(
        _ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls =
            pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        runService { try Self.extractArchives(urls) }
    }

    /// The system waits for a service handler to return, and copying or unpacking a large selection takes
    /// as long as it takes, so the work runs in the background. A failure is shown here: by the time it
    /// happens the handler has returned, and its `error` would only have reached the console anyway.
    @discardableResult
    func runService(_ work: @escaping @Sendable () throws -> [URL]) -> Task<Void, Never> {
        Task.detached {
            do {
                let outputs = try work()
                await MainActor.run {
                    if Settings.shared.revealExtractedInFinder, !outputs.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                }
            } catch {
                await MainActor.run {
                    NSApp.activate()
                    _ = Prompts.makeErrorAlert(for: error).runModal()
                }
            }
        }
    }

    /// Compresses `urls` into a sibling `.zip` archive (or inside `destinationFolder`), numbering if needed.
    nonisolated static func compressFiles(_ urls: [URL], into destinationFolder: URL? = nil) throws -> URL {
        guard let first = urls.first else { throw ArchiveError.unreadable("Nothing to compress.") }
        let folder = destinationFolder ?? first.deletingLastPathComponent()
        let stem = urls.count == 1 ? Naming.stem(of: first) : "Archive"
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = Naming.unique("\(stem).zip", isDirectory: false, taken: taken)
        let output = folder.appendingPathComponent(name)

        let staging = try Workspace()
        defer { staging.discard() }
        var stagedTaken: Set<String> = []
        for url in urls {
            let itemName = Naming.unique(url.lastPathComponent, isDirectory: isDirectory(url), taken: stagedTaken)
            stagedTaken.insert(itemName)
            try FileManager.default.copyItem(at: url, to: staging.contents.appendingPathComponent(itemName))
        }
        try Archive.writeZip(
            from: staging.contents, to: output, compressionLevel: Settings.shared.compressionLevel)
        return output
    }

    /// Extracts each archive in `urls` into `destinationFolder` (or beside each archive), honoring wrapping settings.
    nonisolated static func extractArchives(_ urls: [URL], into destinationFolder: URL? = nil) throws -> [URL] {
        var results: [URL] = []
        for archive in urls {
            let folder = destinationFolder ?? archive.deletingLastPathComponent()
            let staging = try Workspace()
            defer { staging.discard() }
            _ = try Archive.extract(archive, into: staging.contents)
            let topItems = try FileManager.default.contentsOfDirectory(
                at: staging.contents, includingPropertiesForKeys: nil
            ).filter { !EntryPath.isJunk($0.lastPathComponent) }
            guard !topItems.isEmpty else { continue }

            let wrap: Bool =
                switch Settings.shared.wrapExtractedFiles {
                case .whenMultipleItems: topItems.count > 1
                case .always: true
                case .never: false
                }
            var targetFolder = folder
            if wrap {
                let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                let folderName = Naming.unique(Naming.stem(of: archive), isDirectory: true, taken: taken)
                targetFolder = folder.appendingPathComponent(folderName)
                try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: false)
            }
            var taken = Set((try? FileManager.default.contentsOfDirectory(atPath: targetFolder.path)) ?? [])
            var moved: [URL] = []
            for item in topItems {
                let name = Naming.unique(item.lastPathComponent, isDirectory: isDirectory(item), taken: taken)
                taken.insert(name)
                let destination = targetFolder.appendingPathComponent(name)
                try FileManager.default.moveItem(at: item, to: destination)
                moved.append(destination)
            }
            results.append(contentsOf: wrap ? [targetFolder] : moved)
        }
        return results
    }

    /// Archives open as usual. Anything else dropped on the Dock icon, or opened with the app, goes into
    /// a new archive: the untouched empty window if there is one, otherwise a fresh one.
    func application(_ application: NSApplication, open urls: [URL]) {
        let controller = NSDocumentController.shared
        var loose: [URL] = []
        for url in urls {
            if let type = try? controller.typeForContents(of: url), controller.documentClass(forType: type) != nil {
                controller.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { controller.presentError(error) }
                }
            } else {
                loose.append(url)
            }
        }
        guard !loose.isEmpty else { return }
        let document: ArchiveDocument?
        if let empty = controller.documents.compactMap({ $0 as? ArchiveDocument }).first(where: \.isTransient) {
            empty.showWindows()
            document = empty
        } else {
            do {
                document = try controller.openUntitledDocumentAndDisplay(true) as? ArchiveDocument
            } catch {
                controller.presentError(error)
                return
            }
        }
        guard let document else { return }
        document.suggestedName = loose.count == 1 ? loose[0].deletingPathExtension().lastPathComponent : "Archive"
        Task {
            do {
                // Two dropped items can share a name only if they came from different folders.
                try await document.add(loose, into: "") { _ in .keepBoth }
            } catch {
                document.presentError(error)
            }
        }
    }

    /// Opens an empty archive on launch when the user's launch setting asks for one (the default).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        Settings.shared.launchBehavior == .openEmptyArchive
    }
}
