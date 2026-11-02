import AppKit

/// Offline Help guide window (`Help > Zipboy Help`, `⌘?`), searchable across all archive workflows.
@MainActor
final class HelpWindowController: NSWindowController, NSSearchFieldDelegate {
    static let shared = HelpWindowController()

    struct Section: Equatable {
        let title: String
        let summary: String
        let keywords: [String]
    }

    static let allSections: [Section] = [
        Section(
            title: "Opening & Browsing Archives",
            summary:
                "Open ZIP, RAR, 7z, TAR, Gzip, Bzip2, XZ, Zstandard, LHA, CAB, ISO, CPIO, and XAR archives with ⌘O or by dragging them onto Zipboy. Press Space for Quick Look, or double-click a nested archive to open it in its own Zipboy window.",
            keywords: ["open", "browse", "quick look", "space", "nested", "rar", "7z", "tar", "zip"]
        ),
        Section(
            title: "Adding, Renaming, & Deleting Files",
            summary:
                "Drag files and folders from Finder into the archive, or press ⌘⇧A to add files and ⌘⇧N for a new folder. Hovering a dragged item over a collapsed folder for 0.7 seconds springs it open. Press Return to rename, Delete to remove, and ⌘Z to undo any edit.",
            keywords: ["add", "rename", "delete", "new folder", "undo", "redo", "drag", "spring"]
        ),
        Section(
            title: "Extracting & Dragging Out",
            summary:
                "Drag any files or folders out to Finder, press ⌘E to extract to your default destination (configured in Settings), or press ⌥⌘E to choose a destination folder.",
            keywords: ["extract", "unpack", "finder", "drag out", "destination", "wrap"]
        ),
        Section(
            title: "Passwords & AES-256 Encryption",
            summary:
                "Choose File > Set Password… to encrypt the archive with AES-256 when saved, or File > Remove Password to save it unencrypted. Check “Remember password in Keychain” on the password sheet so reopening the archive needs no password prompt.",
            keywords: ["password", "encrypt", "aes", "keychain", "lock", "security", "decrypt"]
        ),
        Section(
            title: "Integrity Verification & Checksums",
            summary:
                "Choose File > Verify Archive (⌘⇧T) or click Verify in the Inspector to test every entry’s integrity without writing files to disk. Select any file to see its CRC-32 and SHA-256 checksums in the right-hand Inspector (⌥⌘I).",
            keywords: ["verify", "checksum", "crc32", "sha256", "integrity", "corrupt", "inspector"]
        ),
        Section(
            title: "Exporting & Legacy Filename Encodings",
            summary:
                "Choose File > Export… (⌘⇧E) to write the archive as .zip, .tar.gz, .tar.xz, .tar, or .7z. If an archive created on another system displays garbled filenames, choose View > Text Encoding to re-read names in Shift-JIS, GB18030, Big5, EUC-KR, Windows-1251, Windows-1252, or CP437.",
            keywords: ["export", "tar", "7z", "encoding", "shift-jis", "gb18030", "cp437", "unicode"]
        ),
    ]

    let searchField = NSSearchField()
    private let stack = NSStackView()
    private(set) var visibleSections: [Section] = allSections

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zipboy Help"
        window.minSize = NSSize(width: 440, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func filter(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            visibleSections = Self.allSections
        } else {
            visibleSections = Self.allSections.filter { section in
                section.title.lowercased().contains(trimmed)
                    || section.summary.lowercased().contains(trimmed)
                    || section.keywords.contains(where: { $0.contains(trimmed) })
            }
        }
        rebuildCards()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter(searchField.stringValue)
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))

        searchField.placeholderString = "Search Help (e.g. password, verify, export)"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedHelpView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scroll.documentView = documentView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        rebuildCards()
        window.contentView = root
    }

    private func rebuildCards() {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for section in visibleSections {
            let box = NSBox()
            box.boxType = .custom
            box.cornerRadius = 8
            box.borderWidth = 1
            box.borderColor = .separatorColor
            box.fillColor = .controlBackgroundColor
            box.contentViewMargins = NSSize(width: 14, height: 12)
            box.translatesAutoresizingMaskIntoConstraints = false

            let inner = NSStackView()
            inner.orientation = .vertical
            inner.alignment = .leading
            inner.spacing = 4

            let heading = NSTextField(labelWithString: section.title)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            heading.textColor = .labelColor

            let body = NSTextField(wrappingLabelWithString: section.summary)
            body.font = .systemFont(ofSize: 12)
            body.textColor = .secondaryLabelColor

            inner.addArrangedSubview(heading)
            inner.addArrangedSubview(body)
            box.contentView = inner
            stack.addArrangedSubview(box)
            box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
    }
}

private final class FlippedHelpView: NSView {
    override var isFlipped: Bool { true }
}
