import AppKit
import Quartz
import UniformTypeIdentifiers
import ZipboyKit

/// The inspector beside the list: a preview well, the item's name, a table of what's known about it,
/// and a footer with the one thing you most likely want to do next. With nothing selected it
/// describes the archive.
@MainActor
final class PreviewViewController: NSViewController {
    private let well = NSView()
    private let quickLook = QLPreviewView(frame: .zero, style: .compact)!
    private let picture = NSImageView()

    private let name = NSTextField(wrappingLabelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let badges = NSStackView()
    let table = InfoTable()

    /// The action buttons and the rule above them; hidden, it gives its space back to the body.
    private let footer = NSView()
    private let buttons = NSStackView()
    private(set) var secondary = ActionButton("", action: nil, prominent: false)
    private(set) var primary = ActionButton("", action: nil, prominent: true)

    private var checksums: [String: Checksums] = [:]
    /// The item on show and its key, so a checksum that finishes late doesn't land on the next one.
    private var showing: (key: String, node: Node, catalogCRC: String?)?

    override func loadView() {

        well.wantsLayer = true
        well.layer?.cornerRadius = Theme.Radius.l
        well.layer?.cornerCurve = .continuous
        well.layer?.borderWidth = 1
        well.layer?.masksToBounds = true
        well.translatesAutoresizingMaskIntoConstraints = false
        quickLook.shouldCloseWithWindow = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        for view in [quickLook, picture] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            well.addSubview(view)
        }

        name.font = Theme.Font.title
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingMiddle
        name.isSelectable = true
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.font = Theme.Font.callout
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badges.orientation = .horizontal
        badges.spacing = Theme.Space.xs

        let heading = NSStackView(views: [name, subtitle, badges])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = Theme.Space.xxs
        heading.setCustomSpacing(Theme.Space.s, after: subtitle)

        let body = NSStackView(views: [well, heading, table])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = Theme.Space.l
        body.setCustomSpacing(Theme.Space.xl, after: heading)
        body.edgeInsets = NSEdgeInsets(
            top: Theme.Space.m, left: Theme.Space.l, bottom: Theme.Space.l, right: Theme.Space.l)
        body.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = Theme.Space.s
        buttons.addArrangedSubview(secondary)
        buttons.addArrangedSubview(primary)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(rule)
        footer.addSubview(buttons)

        let root = NSStackView(views: [scroll, footer])
        root.orientation = .vertical
        root.spacing = 0

        NSLayoutConstraint.activate([
            // `.width` alignment only makes arranged views match each other; these pin them to the edges.
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            body.topAnchor.constraint(equalTo: document.topAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor),

            // Everything in the body shares one left and one right edge.
            well.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * Theme.Space.l),
            heading.widthAnchor.constraint(equalTo: well.widthAnchor),
            table.widthAnchor.constraint(equalTo: well.widthAnchor),
            name.widthAnchor.constraint(lessThanOrEqualTo: heading.widthAnchor),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: heading.widthAnchor),
            {
                // A landscape stage that stops growing once it's big enough to judge a picture by.
                let shape = well.heightAnchor.constraint(equalTo: well.widthAnchor, multiplier: 0.75)
                shape.priority = .defaultHigh
                return shape
            }(),
            well.heightAnchor.constraint(lessThanOrEqualToConstant: 300),

            quickLook.topAnchor.constraint(equalTo: well.topAnchor),
            quickLook.leadingAnchor.constraint(equalTo: well.leadingAnchor),
            quickLook.trailingAnchor.constraint(equalTo: well.trailingAnchor),
            quickLook.bottomAnchor.constraint(equalTo: well.bottomAnchor),
            picture.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            picture.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            picture.widthAnchor.constraint(equalToConstant: 112),
            picture.heightAnchor.constraint(equalToConstant: 112),

            rule.topAnchor.constraint(equalTo: footer.topAnchor),
            rule.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: Theme.Space.m),
            buttons.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: Theme.Space.l),
            buttons.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -Theme.Space.l),
            buttons.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -Theme.Space.m),
        ])
        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        well.layer?.backgroundColor = Theme.cgColor(Theme.well, in: well)
        well.layer?.borderColor = Theme.cgColor(.separatorColor, in: well)
    }

    // MARK: Showing

    /// Shows one item in Quick Look, sums up several, or describes the archive when none is selected.
    func show(_ nodes: [Node], archive: ArchiveDocument) {
        loadViewIfNeeded()
        switch nodes.count {
        case 0: showArchive(archive)
        case 1: showItem(nodes[0], archive: archive)
        default: showSelection(nodes)
        }
    }

    private func showItem(_ node: Node, archive: ArchiveDocument) {
        footer.isHidden = false
        let key = "\(node.url.path)|\(node.size)|\(node.modified?.timeIntervalSince1970 ?? 0)"
        if Self.previewsInQuickLook(node) {
            preview(node.url)
        } else {
            picture(NSWorkspace.shared.icon(forFile: node.url.path))
        }
        name.stringValue = node.name
        subtitle.stringValue = "\(node.kind) · \(formatSize(node.size))"
        setBadges([])

        let catalogCRC = archive.verbatimEntry(forPath: node.path).map { String(format: "%08X", $0.crc32) }
        showing = (key, node, catalogCRC)
        table.show(Self.rows(for: node, checksums: checksums[key], catalogCRC: catalogCRC))

        // Checksums are worth showing, not worth waiting for: they fill in when they're ready.
        if Self.isFile(node), checksums[key] == nil, node.size <= 64 << 20 {
            let url = node.url
            Task.detached { [weak self] in
                // An unreadable file keeps the rows it has; there's nothing for the person to do about it.
                guard let computed = try? Checksums.compute(for: url) else { return }
                await self?.checksumsArrived(computed, key: key)
            }
        }

        let opensInside = node.isDirectory || BrowserViewController.isNestedArchive(node.url)
        actions(
            secondary: opensInside
                ? ("Open", #selector(BrowserViewController.openItems(_:)))
                : ("Quick Look", #selector(BrowserViewController.toggleQuickLook(_:))),
            primary: ("Extract", #selector(BrowserViewController.extract(_:))),
            enabled: true)
    }

    private func checksumsArrived(_ computed: Checksums, key: String) {
        checksums[key] = computed
        guard let showing, showing.key == key else { return }
        table.show(Self.rows(for: showing.node, checksums: computed, catalogCRC: showing.catalogCRC))
    }

    private func showArchive(_ archive: ArchiveDocument) {
        showing = nil
        let icon =
            archive.source.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .zip)
        picture(icon)

        let tree = archive.tree
        let count = tree?.descendantCount ?? 0
        let unpacked = tree?.size ?? 0
        name.stringValue = archive.displayName
        subtitle.stringValue = count == 0 ? "Empty archive" : "\(Self.items(count)) · \(formatSize(unpacked))"
        var marks: [(String, String)] = []
        if archive.password != nil { marks.append(("lock.fill", "Encrypted")) }
        if let imported = archive.importedFrom {
            marks.append(("arrow.triangle.2.circlepath", "\(imported.format) · saves as ZIP"))
        }
        setBadges(marks)

        let onDisk = archive.source.flatMap(Self.fileBytes)
        let modified = archive.source.flatMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        // An empty archive has nothing to tabulate or act on; the list's drop tray says what to do.
        footer.isHidden = count == 0
        guard count > 0 else {
            table.show([])
            return
        }
        table.show([
            ("Contains", Self.breakdown(of: tree)),
            ("Unpacked", formatSize(unpacked)),
            onDisk.map { ("Compressed", Self.compressed($0, from: unpacked)) },
            // An imported archive's badge already names its format.
            archive.importedFrom == nil ? ("Format", "ZIP") : nil,
            modified.map { ("Modified", Self.date($0)) },
        ])

        actions(
            secondary: ("Verify", #selector(ArchiveDocument.verifyArchive(_:))),
            primary: ("Extract All", #selector(BrowserViewController.extract(_:))),
            enabled: true)
    }

    private func showSelection(_ nodes: [Node]) {
        showing = nil
        footer.isHidden = false
        picture(Self.fan(nodes.prefix(3).map { NSWorkspace.shared.icon(forFile: $0.url.path) }))
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        let folders = nodes.filter(\.isDirectory).count
        name.stringValue = "\(nodes.count.formatted()) Items"
        subtitle.stringValue = formatSize(total)
        setBadges([])
        table.show([
            ("Contains", Self.counts(files: nodes.count - folders, folders: folders)),
            ("Size", formatSize(total)),
        ])
        actions(
            secondary: ("Quick Look", #selector(BrowserViewController.toggleQuickLook(_:))),
            primary: ("Extract", #selector(BrowserViewController.extract(_:))),
            enabled: true)
    }

    // MARK: Parts

    /// Folders, links, and archives show their icon: Quick Look's card for them only repeats the table.
    private static func previewsInQuickLook(_ node: Node) -> Bool {
        isFile(node) && !ZipMethod.archiveExtensions.contains(node.url.pathExtension.lowercased())
    }

    private func preview(_ url: URL) {
        picture.isHidden = true
        quickLook.isHidden = false
        if (quickLook.previewItem as? NSURL) as URL? == url {
            quickLook.refreshPreviewItem()
        } else {
            quickLook.previewItem = url as NSURL
        }
    }

    private func picture(_ image: NSImage) {
        quickLook.previewItem = nil
        quickLook.isHidden = true
        picture.image = image
        picture.isHidden = false
    }

    private func setBadges(_ marks: [(symbol: String, text: String)]) {
        badges.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for mark in marks { badges.addArrangedSubview(Badge(symbol: mark.symbol, text: mark.text)) }
        badges.isHidden = marks.isEmpty
    }

    private func actions(
        secondary: (title: String, action: Selector), primary: (title: String, action: Selector), enabled: Bool
    ) {
        self.secondary.label = secondary.title
        self.secondary.action = secondary.action
        self.secondary.isEnabled = enabled
        self.primary.label = primary.title
        self.primary.action = primary.action
        self.primary.isEnabled = enabled
    }

    private static func rows(for node: Node, checksums: Checksums?, catalogCRC: String?) -> [(String, String)?] {
        let folder = (node.path as NSString).deletingLastPathComponent
        let target = node.isSymlink ? (try? FileManager.default.destinationOfSymbolicLink(atPath: node.url.path)) : nil
        return [
            node.isDirectory ? ("Contains", items(node.descendantCount)) : nil,
            ("Size", exactSize(node)),
            ("Where", folder.isEmpty ? "Top level" : folder),
            target.map { ("Points to", $0) },
            ("Modified", node.modified.map(date) ?? "—"),
            isFile(node) ? (checksums?.crc32Hex ?? catalogCRC).map { ("CRC-32", $0) } : nil,
            isFile(node) ? checksums.map { ("SHA-256", $0.sha256Hex) } : nil,
        ]
    }

    private static func isFile(_ node: Node) -> Bool { !node.isDirectory && !node.isSymlink }

    private static func breakdown(of tree: Node?) -> String {
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
        if let tree { walk(tree) }
        return counts(files: files, folders: folders)
    }

    private static func counts(files: Int, folders: Int) -> String {
        var parts: [String] = []
        if files > 0 { parts.append(files == 1 ? "1 file" : "\(files.formatted()) files") }
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders.formatted()) folders") }
        return parts.isEmpty ? "Nothing" : parts.joined(separator: ", ")
    }

    private static func compressed(_ bytes: Int64, from unpacked: Int64) -> String {
        let text = formatSize(bytes)
        guard unpacked > 0, bytes < unpacked else { return text }
        let saved = Int((1 - Double(bytes) / Double(unpacked)) * 100)
        return saved > 0 ? "\(text), \(saved)% smaller" : text
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

    private static func exactSize(_ node: Node) -> String {
        let text = formatSize(node.size)
        guard !node.isDirectory, node.size >= 1000 else { return text }
        return "\(text) (\(node.size.formatted()) bytes)"
    }

    private static func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private static func fileBytes(_ url: URL) -> Int64? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Facts about an item as label–value rows, every row spanning the full width so labels and values
/// line up on two clean edges, with hairlines between.
@MainActor
final class InfoTable: NSView {
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("InfoTable is built in code") }

    /// The rows on show, for tests.
    var rows: [NSView] { stack.arrangedSubviews.filter { !($0 is NSBox) } }

    func show(_ entries: [(String, String)?]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, (label, value)) in entries.compactMap({ $0 }).enumerated() {
            if index > 0 {
                let rule = NSBox()
                rule.boxType = .separator
                stack.addArrangedSubview(rule)
                rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let row = Self.row(label, value)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private static func row(_ label: String, _ value: String) -> NSView {
        let key = NSTextField(labelWithString: label)
        key.font = Theme.Font.callout
        key.textColor = .secondaryLabelColor
        key.setContentHuggingPriority(.required, for: .horizontal)
        key.setContentCompressionResistancePriority(.required, for: .horizontal)

        let field = NSTextField(labelWithString: value)
        // Hashes are read in groups, so they get fixed-width digits; everything else reads as text.
        let isHash = label == "SHA-256" || label == "CRC-32"
        field.font = isHash ? Theme.Font.code : Theme.Font.callout
        field.alignment = .right
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingMiddle
        field.toolTip = value
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        for part in [key, field] {
            part.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(part)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 28),
            key.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            key.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            field.leadingAnchor.constraint(greaterThanOrEqualTo: key.trailingAnchor, constant: Theme.Space.m),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            field.firstBaselineAnchor.constraint(equalTo: key.firstBaselineAnchor),
        ])
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        row.setAccessibilityLabel("\(label): \(value)")
        return row
    }
}

/// A small fact about the archive as a whole, like being encrypted, set as a quiet pill.
@MainActor
final class Badge: NSView {
    init(symbol: String, text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        let icon = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: text)
        label.font = Theme.Font.label
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [icon, label])
        row.spacing = Theme.Space.xs
        row.edgeInsets = NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError("Badge is built in code") }

    override func updateLayer() {
        layer?.backgroundColor = Theme.cgColor(Theme.quiet, in: self)
    }

    override var wantsUpdateLayer: Bool { true }
}

/// A document view that lays out from the top, as reading order does.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// File sizes as Finder writes them, except "0 bytes" rather than "Zero KB".
func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
