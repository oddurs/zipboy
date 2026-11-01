import AppKit
import Quartz
import UniformTypeIdentifiers
import ZipboyKit

/// The right-hand inspector: a live Quick Look preview (or crisp icon stage for folders, multi-selection,
/// and the archive overview), followed by Finder-style identity headers, an Information table with
/// hairline dividers, and contextual quick-action buttons.
@MainActor
final class PreviewViewController: NSViewController {
    private let stage = NSView()
    private let well = NSView()
    private let quickLook = QLPreviewView(frame: .zero, style: .compact)!
    private let card = NSView()
    private let clip = NSView()
    private let placeholder = NSImageView()

    private let name = NSTextField(wrappingLabelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let infoHeader = NSTextField(labelWithString: "Information")
    private let rowsStack = NSStackView()
    private let actionsStack = NSStackView()

    override func loadView() {
        let root = NSView()

        stage.translatesAutoresizingMaskIntoConstraints = false

        well.translatesAutoresizingMaskIntoConstraints = false
        well.wantsLayer = true
        well.layer?.cornerRadius = 10
        well.layer?.cornerCurve = .continuous
        well.layer?.borderWidth = 0.5

        quickLook.translatesAutoresizingMaskIntoConstraints = false
        quickLook.shouldCloseWithWindow = true

        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.shadow = NSShadow()
        card.layer?.shadowOpacity = 0.10
        card.layer?.shadowRadius = 6
        card.layer?.shadowOffset = CGSize(width: 0, height: -2)

        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 10
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 0.5
        clip.addSubview(quickLook)
        card.addSubview(clip)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.imageScaling = .scaleProportionallyUpOrDown

        stage.addSubview(well)
        stage.addSubview(card)
        stage.addSubview(placeholder)

        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .labelColor
        name.alignment = .left
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingMiddle
        name.isSelectable = true

        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .left
        subtitle.lineBreakMode = .byTruncatingTail

        let titleGroup = NSStackView(views: [name, subtitle])
        titleGroup.orientation = .vertical
        titleGroup.alignment = .leading
        titleGroup.spacing = 2

        let topRule = Self.hairline()

        infoHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        infoHeader.textColor = .secondaryLabelColor

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0

        let bottomRule = Self.hairline()

        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.distribution = .fillEqually
        actionsStack.spacing = 8

        let details = NSStackView(views: [
            titleGroup,
            topRule,
            infoHeader,
            rowsStack,
            bottomRule,
            actionsStack,
        ])
        details.orientation = .vertical
        details.alignment = .width
        details.spacing = 8
        details.setCustomSpacing(10, after: titleGroup)
        details.setCustomSpacing(10, after: topRule)
        details.setCustomSpacing(4, after: infoHeader)
        details.setCustomSpacing(10, after: rowsStack)
        details.setCustomSpacing(10, after: bottomRule)
        details.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stage)
        root.addSubview(details)

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 14),
            stage.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stage.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stage.bottomAnchor.constraint(equalTo: details.topAnchor, constant: -14),
            stage.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            well.topAnchor.constraint(equalTo: stage.topAnchor),
            well.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            well.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            well.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            card.topAnchor.constraint(equalTo: stage.topAnchor),
            card.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            clip.topAnchor.constraint(equalTo: card.topAnchor),
            clip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            clip.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            quickLook.topAnchor.constraint(equalTo: clip.topAnchor),
            quickLook.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            quickLook.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            quickLook.bottomAnchor.constraint(equalTo: clip.bottomAnchor),

            placeholder.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 96),
            placeholder.heightAnchor.constraint(equalToConstant: 96),

            details.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            details.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            details.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            name.widthAnchor.constraint(lessThanOrEqualTo: details.widthAnchor),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: details.widthAnchor),
        ])
        view = root
    }

    /// Shows one item in Quick Look, sums up several, or describes the archive when none is selected.
    func show(_ nodes: [Node], archive: ArchiveDocument) {
        loadViewIfNeeded()
        if nodes.count == 1, let node = nodes.first {
            if Self.shouldUseQuickLook(for: node) {
                preview(node.url)
            } else {
                let icon = NSWorkspace.shared.icon(forFile: node.url.path)
                icon.size = NSSize(width: 96, height: 96)
                picture(icon)
            }
            name.stringValue = node.name
            subtitle.stringValue = "\(node.kind) — \(formatSize(node.size))"
            let parentFolder = (node.path as NSString).deletingLastPathComponent
            let linkTarget =
                node.isSymlink
                ? (try? FileManager.default.destinationOfSymbolicLink(atPath: node.url.path))
                : nil
            details([
                ("Kind", node.kind),
                ("Size", size(node)),
                node.isDirectory ? ("Contains", items(node.descendantCount)) : nil,
                ("Location", parentFolder.isEmpty ? "Top Level" : parentFolder),
                linkTarget.map { ("Points To", $0) },
                ("Modified", node.modified.map(Self.date) ?? "—"),
            ])
            configureActions([
                node.isDirectory
                    ? ("Open", "folder", #selector(BrowserViewController.openItems(_:)), true)
                    : ("Quick Look", "eye", #selector(BrowserViewController.toggleQuickLook(_:)), true),
                ("Extract", "arrow.down.to.line", #selector(BrowserViewController.extract(_:)), true),
                ("Rename", "pencil", #selector(BrowserViewController.rename(_:)), true),
                ("Delete", "trash", #selector(BrowserViewController.delete(_:)), true),
            ])
        } else if nodes.isEmpty {
            let icon =
                archive.source.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSWorkspace.shared.icon(for: .zip)
            icon.size = NSSize(width: 96, height: 96)
            picture(icon)

            name.stringValue = archive.displayName
            let tree = archive.tree
            let totalItems = tree?.descendantCount ?? 0
            let unpackedBytes = tree?.size ?? 0
            let format = archive.importedFrom.map { "\($0.format) Archive" } ?? "ZIP Archive"
            subtitle.stringValue =
                totalItems == 0
                ? "Empty \(format)"
                : "\(format) — \(items(totalItems))"

            let diskBytes = archive.source.flatMap(Self.fileBytes)
            let diskDescription: String? = diskBytes.map { bytes in
                let formatted = formatSize(bytes)
                if unpackedBytes > 0, bytes < unpackedBytes {
                    let saved = Int(round((1.0 - Double(bytes) / Double(unpackedBytes)) * 100))
                    if saved > 0 { return "\(formatted) (\(saved)% smaller)" }
                }
                return formatted
            }
            let archiveModified = archive.source.flatMap {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }

            details([
                ("Format", archive.importedFrom.map { "\($0.format) (saves as ZIP)" } ?? "ZIP"),
                ("Security", archive.password == nil ? "None" : "AES-256 Encrypted"),
                ("Contains", Self.breakdown(of: tree)),
                ("Unpacked", formatSize(unpackedBytes)),
                diskDescription.map { ("On Disk", $0) },
                archiveModified.map { ("Modified", Self.date($0)) },
            ])
            let hasItems = totalItems > 0
            configureActions([
                ("Add Files", "plus", #selector(BrowserViewController.addFiles(_:)), true),
                ("New Folder", "folder.badge.plus", #selector(BrowserViewController.newFolder(_:)), true),
                (
                    archive.password == nil ? "Lock" : "Password",
                    archive.password == nil ? "lock" : "lock.fill",
                    #selector(ArchiveDocument.choosePassword(_:)),
                    true
                ),
                ("Extract All", "arrow.down.to.line", #selector(BrowserViewController.extract(_:)), hasItems),
            ])
        } else {
            picture(Self.fan(nodes.prefix(3).map { NSWorkspace.shared.icon(forFile: $0.url.path) }))
            name.stringValue = "\(nodes.count.formatted()) Items Selected"
            let total = nodes.reduce(Int64(0)) { $0 + $1.size }
            let folderCount = nodes.filter(\.isDirectory).count
            let fileCount = nodes.count - folderCount
            subtitle.stringValue = "\(Self.countsText(files: fileCount, folders: folderCount)) — \(formatSize(total))"
            details([
                ("Selection", Self.countsText(files: fileCount, folders: folderCount)),
                ("Total Size", formatSize(total)),
            ])
            configureActions([
                ("Quick Look", "eye", #selector(BrowserViewController.toggleQuickLook(_:)), true),
                ("Open", "arrow.up.forward.app", #selector(BrowserViewController.openItems(_:)), true),
                ("Extract", "arrow.down.to.line", #selector(BrowserViewController.extract(_:)), true),
                ("Delete", "trash", #selector(BrowserViewController.delete(_:)), true),
            ])
        }
    }

    /// Folders, symlinks, and nested archives show a clean icon in the stage rather than Quick Look's
    /// generic info card, which would duplicate the inspector's own metadata below.
    private static func shouldUseQuickLook(for node: Node) -> Bool {
        guard !node.isDirectory, !node.isSymlink else { return false }
        let ext = node.url.pathExtension.lowercased()
        if ZipMethod.archiveExtensions.contains(ext) { return false }
        return true
    }

    private func preview(_ url: URL) {
        placeholder.isHidden = true
        well.isHidden = true
        card.isHidden = false
        if (quickLook.previewItem as? NSURL) as URL? == url {
            quickLook.refreshPreviewItem()
        } else {
            quickLook.previewItem = url as NSURL
        }
    }

    private func picture(_ image: NSImage?) {
        quickLook.previewItem = nil
        card.isHidden = true
        well.isHidden = false
        placeholder.image = image
        placeholder.isHidden = false
    }

    private func details(_ rows: [(String, String)?]) {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let entries = rows.compactMap { $0 }
        for (index, (label, value)) in entries.enumerated() {
            if index > 0 {
                rowsStack.addArrangedSubview(Self.hairline())
            }
            let key = NSTextField(labelWithString: label)
            key.font = .systemFont(ofSize: 12)
            key.textColor = .secondaryLabelColor
            key.setContentHuggingPriority(.required, for: .horizontal)
            key.setContentCompressionResistancePriority(.required, for: .horizontal)

            let field = NSTextField(labelWithString: value)
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.textColor = .labelColor
            field.alignment = .right
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingMiddle
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let row = NSStackView(views: [key, field])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.distribution = .fill
            row.spacing = 12
            row.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
            rowsStack.addArrangedSubview(row)
        }
    }

    private func configureActions(_ specs: [(title: String, symbol: String, action: Selector, enabled: Bool)]) {
        actionsStack.arrangedSubviews.forEach { view in
            actionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for spec in specs {
            let button = NSButton(frame: .zero)
            button.bezelStyle = .rounded
            button.isBordered = false
            button.imagePosition = .imageAbove
            button.title = spec.title
            button.font = .systemFont(ofSize: 10, weight: .medium)
            if let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.title) {
                button.image = image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            }
            button.contentTintColor = spec.enabled ? .secondaryLabelColor : .quaternaryLabelColor
            button.action = spec.action
            button.target = nil
            button.isEnabled = spec.enabled
            button.setAccessibilityLabel(spec.title)
            actionsStack.addArrangedSubview(button)
        }
    }

    private static func breakdown(of tree: Node?) -> String {
        guard let tree else { return "0 items" }
        var files = 0
        var folders = 0
        func walk(_ node: Node) {
            for child in node.children {
                if child.isDirectory {
                    folders += 1
                    walk(child)
                } else {
                    files += 1
                }
            }
        }
        walk(tree)
        if files == 0 && folders == 0 { return "0 items" }
        return countsText(files: files, folders: folders)
    }

    private static func countsText(files: Int, folders: Int) -> String {
        var parts: [String] = []
        if files > 0 { parts.append(files == 1 ? "1 file" : "\(files.formatted()) files") }
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders.formatted()) folders") }
        return parts.isEmpty ? "0 items" : parts.joined(separator: ", ")
    }

    /// Up to three icons fanned out like cards in a hand, for a selection of several items.
    private static func fan(_ icons: [NSImage]) -> NSImage {
        let side: CGFloat = 112
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            let angles: [CGFloat] = icons.count == 1 ? [0] : icons.count == 2 ? [8, -8] : [12, 0, -12]
            for (icon, angle) in zip(icons, angles) {
                NSGraphicsContext.saveGraphicsState()
                let turn = NSAffineTransform()
                turn.translateX(by: bounds.midX, yBy: bounds.minY + 12)
                turn.rotate(byDegrees: angle)
                turn.translateX(by: -bounds.midX, yBy: -(bounds.minY + 12))
                turn.concat()
                icon.draw(in: bounds.insetBy(dx: 16, dy: 16))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    private func size(_ node: Node) -> String {
        let text = formatSize(node.size)
        guard !node.isDirectory, node.size >= 1000 else { return text }
        return "\(text) (\(node.size.formatted()) B)"
    }

    private func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private static func fileBytes(_ url: URL) -> Int64? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }

    private static func hairline() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
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
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            well.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.14).cgColor
            well.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
            clip.layer?.borderColor = NSColor.separatorColor.cgColor
            card.layer?.shadowColor = NSColor.shadowColor.cgColor
        }
    }
}
