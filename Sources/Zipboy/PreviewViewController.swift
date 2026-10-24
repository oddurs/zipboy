import AppKit
import Quartz
import UniformTypeIdentifiers
import ZipboyKit

/// The inspector: a live Quick Look of the selection with its details underneath. With nothing
/// selected it describes the archive.
@MainActor
final class PreviewViewController: NSViewController {
    private let quickLook = QLPreviewView(frame: .zero, style: .normal)!
    private let placeholder = NSImageView()
    private let name = NSTextField(wrappingLabelWithString: "")
    private let grid = NSGridView()
    /// The preview sits on a card: a shadow outside, rounded corners clipping inside.
    private let card = NSView()
    private let clip = NSView()

    override func loadView() {
        let root = NSView()
        quickLook.translatesAutoresizingMaskIntoConstraints = false
        quickLook.shouldCloseWithWindow = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.shadow = NSShadow()
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 10
        card.layer?.shadowOffset = CGSize(width: 0, height: -3)
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 14
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 0.5
        clip.addSubview(quickLook)
        card.addSubview(clip)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.imageScaling = .scaleProportionallyUpOrDown

        name.font = Theme.rounded(15, .semibold)
        name.alignment = .center
        name.maximumNumberOfLines = 3
        name.lineBreakMode = .byTruncatingMiddle
        name.isSelectable = true

        grid.rowSpacing = 7
        grid.columnSpacing = 12

        let details = NSStackView(views: [name, grid])
        details.orientation = .vertical
        details.alignment = .centerX
        details.spacing = 14
        details.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(card)
        root.addSubview(placeholder)
        root.addSubview(details)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: details.topAnchor, constant: -20),
            clip.topAnchor.constraint(equalTo: card.topAnchor),
            clip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            clip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            quickLook.topAnchor.constraint(equalTo: clip.topAnchor),
            quickLook.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            quickLook.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            quickLook.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 128),
            placeholder.heightAnchor.constraint(equalToConstant: 128),
            details.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            details.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            details.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            name.widthAnchor.constraint(lessThanOrEqualTo: details.widthAnchor),
        ])
        view = root
    }

    /// Shows one item in Quick Look, or sums up several, or describes the archive when none is selected.
    func show(_ nodes: [Node], archive: ArchiveDocument) {
        loadViewIfNeeded()
        if nodes.count == 1, let node = nodes.first {
            preview(node.url)
            name.stringValue = node.name
            details([
                ("Kind", node.kind),
                ("Size", size(node)),
                ("Modified", node.modified.map(Self.date) ?? "—"),
                node.isDirectory ? ("Contains", items(node.descendantCount)) : nil,
            ])
        } else if nodes.isEmpty {
            if let url = archive.source {
                preview(url)
            } else {
                picture(NSWorkspace.shared.icon(for: .zip))
            }
            name.stringValue = archive.displayName
            let tree = archive.tree
            details([
                ("Format", archive.importedFrom.map { "\($0.format), saves as ZIP" } ?? "ZIP"),
                archive.password == nil ? nil : ("Password", "Protected with AES-256"),
                ("Contains", items(tree?.descendantCount ?? 0)),
                ("Unpacked", formatSize(tree?.size ?? 0)),
                archive.source.flatMap(Self.fileSize).map { ("On Disk", $0) },
            ])
        } else {
            picture(Self.fan(nodes.prefix(3).map { NSWorkspace.shared.icon(forFile: $0.url.path) }))
            name.stringValue = items(nodes.count)
            let total = nodes.reduce(Int64(0)) { $0 + $1.size }
            details([("Size", formatSize(total))])
        }
    }

    private func preview(_ url: URL) {
        placeholder.isHidden = true
        card.isHidden = false
        // Same file again means it changed underneath, as when another app saved over it.
        if (quickLook.previewItem as? NSURL) as URL? == url {
            quickLook.refreshPreviewItem()
        } else {
            quickLook.previewItem = url as NSURL
        }
    }

    private func picture(_ image: NSImage?) {
        quickLook.previewItem = nil
        card.isHidden = true
        placeholder.image = image
        placeholder.isHidden = false
    }

    private func details(_ rows: [(String, String)?]) {
        // Removing a row leaves its views behind, so they go first.
        grid.subviews.forEach { $0.removeFromSuperview() }
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        for case let (label, value)? in rows {
            // Small uppercase keys, so the values carry the weight.
            let key = NSTextField(
                labelWithAttributedString: NSAttributedString(
                    string: label.uppercased(),
                    attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .kern: 0.6]))
            key.textColor = .tertiaryLabelColor
            key.alignment = .right
            let field = NSTextField(labelWithString: value)
            field.font = .systemFont(ofSize: 12)
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingMiddle
            grid.addRow(with: [key, field])
        }
        if grid.numberOfColumns > 0 {
            grid.column(at: 0).xPlacement = .trailing
            grid.rowAlignment = .firstBaseline
        }
    }

    /// Up to three icons fanned out like cards in a hand, for a selection of several items.
    private static func fan(_ icons: [NSImage]) -> NSImage {
        let side: CGFloat = 128
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            let angles: [CGFloat] = icons.count == 1 ? [0] : icons.count == 2 ? [8, -8] : [12, 0, -12]
            for (icon, angle) in zip(icons, angles) {
                NSGraphicsContext.saveGraphicsState()
                let turn = NSAffineTransform()
                turn.translateX(by: bounds.midX, yBy: bounds.minY + 12)
                turn.rotate(byDegrees: angle)
                turn.translateX(by: -bounds.midX, yBy: -(bounds.minY + 12))
                turn.concat()
                icon.draw(in: bounds.insetBy(dx: 18, dy: 18))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    private func size(_ node: Node) -> String {
        let text = formatSize(node.size)
        guard !node.isDirectory, node.size >= 1000 else { return text }
        return "\(text) (\(node.size.formatted()) bytes)"
    }

    private func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private static func fileSize(_ url: URL) -> String? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return formatSize(Int64(size))
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// File sizes as Finder writes them, except "0 bytes" rather than "Zero KB".
func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}

extension PreviewViewController {
    override func viewDidLayout() {
        super.viewDidLayout()
        // A CGColor doesn't follow the appearance by itself.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            clip.layer?.borderColor = NSColor.separatorColor.cgColor
            card.layer?.shadowColor = NSColor.shadowColor.cgColor
        }
    }
}
