import AppKit
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

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }

    // MARK: Finder Services

    @objc func compressWithZipboy(
        _ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls =
            pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        do {
            let output = try Self.compressFiles(urls)
            if Settings.shared.revealExtractedInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
        } catch let failure {
            error.pointee = failure.localizedDescription as NSString
        }
    }

    @objc func extractWithZipboy(
        _ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls =
            pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        do {
            let outputs = try Self.extractArchives(urls)
            if Settings.shared.revealExtractedInFinder, !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
        } catch let failure {
            error.pointee = failure.localizedDescription as NSString
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
