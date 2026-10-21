import AppKit

/// Closes the untouched Untitled window from launch when an archive opens, so opening a file from
/// Finder shows one window, not two.
@MainActor
final class DocumentController: NSDocumentController {
    override func addDocument(_ document: NSDocument) {
        let transient = documents.compactMap { $0 as? ArchiveDocument }.filter(\.isTransient)
        super.addDocument(document)
        guard document.fileURL != nil else { return }
        for untitled in transient where untitled !== document {
            // Next turn, once the new window is up, so the app never has no window at all.
            DispatchQueue.main.async { untitled.close() }
        }
    }
}
