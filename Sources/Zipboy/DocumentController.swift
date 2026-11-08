import AppKit
import ZipboyKit

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

    /// Maps every supported archive extension to a document type even when LaunchServices has not
    /// indexed the imported UTTypes yet. Plain `.zip` opens in place as an Editor; every other archive
    /// opens as a Viewer so its original file is never overwritten.
    override func typeForContents(of url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" { return ArchiveDocument.zipType }
        if ZipMethod.archiveExtensions.contains(ext) { return "public.archive" }
        return try super.typeForContents(of: url)
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        if typeName == ArchiveDocument.zipType || typeName == "public.archive" {
            return ArchiveDocument.self
        }
        return super.documentClass(forType: typeName)
    }
}
