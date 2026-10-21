import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The first controller made becomes the shared one.
        _ = DocumentController()
        // Workspaces outlive the app only when it crashed, so whatever is there now is abandoned.
        Workspace.removeAbandoned()
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

    /// An empty archive to drop files into is the most useful thing to show on a plain launch.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}
