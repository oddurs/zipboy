import OSLog
import QuickLookUI
import ZipboyKit

/// Finder's Space-bar preview of an archive: its tree of folders and files, listed without unpacking.
@objc(ZipboyPreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let log = Logger(subsystem: "com.oddurs.zipboy.quicklook", category: "preview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let started = ContinuousClock.now
        let listing: ArchiveListing
        do {
            listing = try Archive.list(url)
        } catch {
            // Quick Look falls back to the archive's icon; the log says why.
            Self.log.error("can't list \(url.lastPathComponent, privacy: .private): \(error.localizedDescription)")
            throw error
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        let html = ArchivePreview.html(for: listing, name: url.lastPathComponent, fileSize: fileSize)
        // How long Finder waits, which has a budget: 300 ms for 10,000 entries.
        Self.log.notice("listed \(listing.entries.count) entries in \(started.duration(to: .now), privacy: .public)")
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
    }
}
