import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ZipboyKit

/// Finder's icon for an archive: the archive's own icon with its first picture set into it, or with
/// how many items it holds when it has no pictures.
@objc(ZipboyThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let side = min(request.maximumSize.width, request.maximumSize.height)
        let picture = Archive.firstImage(in: url).flatMap { NSImage(data: $0.data) }
        // A count is unreadable at list-view sizes, so it's worked out only for icons big enough to show it.
        let count = picture == nil && side >= 64 ? (try? Archive.list(url, limit: 100_000)) : nil
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .zip)
        let reply = QLThumbnailReply(contextSize: CGSize(width: side, height: side)) {
            let bounds = NSRect(x: 0, y: 0, width: side, height: side)
            icon.draw(in: bounds)
            if let picture {
                Self.inset(picture, in: bounds)
            } else if let count, !count.namesHidden {
                let text =
                    count.entries.count == 1
                    ? "1 item" : "\(count.entries.count.formatted())\(count.isTruncated ? "+" : "") items"
                Self.badge(text, in: bounds)
            }
            return true
        }
        handler(reply, nil)
    }

    /// The picture fills the page of the document icon, over the zipper, with a white mat as a print has.
    private static func inset(_ picture: NSImage, in bounds: NSRect) {
        let page = NSRect(
            x: bounds.width * 0.24, y: bounds.height * 0.22, width: bounds.width * 0.52, height: bounds.height * 0.56)
        let aspect = picture.size.width / max(picture.size.height, 1)
        var frame = page
        if aspect > page.width / page.height {
            frame.size.height = page.width / aspect
        } else {
            frame.size.width = page.height * aspect
        }
        frame.origin = NSPoint(x: page.midX - frame.width / 2, y: page.midY - frame.height / 2)
        let mat = max(1, bounds.width * 0.012)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = bounds.width * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.width * 0.006)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.set()
        NSColor.white.setFill()
        frame.insetBy(dx: -mat, dy: -mat).fill()
        NSGraphicsContext.restoreGraphicsState()
        picture.draw(in: frame)
    }

    /// The item count as a pill below the zipper, clear of the format name the icon prints at its foot.
    private static func badge(_ text: String, in bounds: NSRect) {
        let font = NSFont.systemFont(ofSize: bounds.width * 0.06, weight: .semibold)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = label.size()
        let pill = NSRect(
            x: bounds.midX - size.width / 2 - font.pointSize * 0.6, y: bounds.height * 0.3,
            width: size.width + font.pointSize * 1.2, height: size.height + font.pointSize * 0.3)
        NSColor(white: 0.25, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        label.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
    }
}
