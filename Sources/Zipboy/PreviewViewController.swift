import AppKit
import Quartz
import ZipboyKit

/// The inspector: a live Quick Look of the selection with its details underneath. With nothing
/// selected it describes the archive.
@MainActor
final class PreviewViewController: NSViewController {
    private let quickLook = QLPreviewView(frame: .zero, style: .normal)!
    private let placeholder = NSImageView()
    private let name = NSTextField(wrappingLabelWithString: "")
    private let grid = NSGridView()

    override func loadView() {
        let root = NSView()
        quickLook.translatesAutoresizingMaskIntoConstraints = false
        quickLook.shouldCloseWithWindow = true

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.imageScaling = .scaleProportionallyUpOrDown

        name.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        name.alignment = .center
        name.maximumNumberOfLines = 3
        name.lineBreakMode = .byTruncatingMiddle
        name.isSelectable = true

        grid.rowSpacing = 6
        grid.columnSpacing = 10

        let details = NSStackView(views: [name, grid])
        details.orientation = .vertical
        details.alignment = .centerX
        details.spacing = 14
        details.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(quickLook)
        root.addSubview(placeholder)
        root.addSubview(details)
        NSLayoutConstraint.activate([
            quickLook.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 12),
            quickLook.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            quickLook.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            quickLook.bottomAnchor.constraint(equalTo: details.topAnchor, constant: -16),
            placeholder.centerXAnchor.constraint(equalTo: quickLook.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: quickLook.centerYAnchor),
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
                picture(NSImage(named: NSImage.multipleDocumentsName))
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
            picture(NSImage(named: NSImage.multipleDocumentsName))
            name.stringValue = items(nodes.count)
            let total = nodes.reduce(Int64(0)) { $0 + $1.size }
            details([("Size", formatSize(total))])
        }
    }

    private func preview(_ url: URL) {
        placeholder.isHidden = true
        quickLook.isHidden = false
        // Same file again means it changed underneath, as when another app saved over it.
        if (quickLook.previewItem as? NSURL) as URL? == url {
            quickLook.refreshPreviewItem()
        } else {
            quickLook.previewItem = url as NSURL
        }
    }

    private func picture(_ image: NSImage?) {
        quickLook.previewItem = nil
        quickLook.isHidden = true
        placeholder.image = image
        placeholder.isHidden = false
    }

    private func details(_ rows: [(String, String)?]) {
        // Removing a row leaves its views behind, so they go first.
        grid.subviews.forEach { $0.removeFromSuperview() }
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        for case let (label, value)? in rows {
            let key = NSTextField(labelWithString: label)
            key.textColor = .secondaryLabelColor
            key.alignment = .right
            let field = NSTextField(labelWithString: value)
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingMiddle
            grid.addRow(with: [key, field])
        }
        if grid.numberOfColumns > 0 { grid.column(at: 0).xPlacement = .trailing }
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
