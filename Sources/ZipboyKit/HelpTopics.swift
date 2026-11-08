import Foundation

/// What Zipboy's help says, written once: the in-app help window shows it, and `ZipboyHelpBook` writes
/// it out as the Apple Help Book that the Help menu's search field finds.
public enum HelpTopics {
    public struct Topic: Equatable, Sendable {
        /// The page's name in the book, and the anchor Help Viewer can open it at.
        public let anchor: String
        public let title: String
        public let summary: String
        public let keywords: [String]
    }

    public static let all: [Topic] = [
        Topic(
            anchor: "open", title: "Opening & Browsing Archives",
            summary:
                "Open ZIP, RAR, 7z, TAR, Gzip, Bzip2, XZ, LHA, CAB, ISO, CPIO, and XAR archives with ⌘O or by dragging them onto Zipboy. Browse a Finder-style list with thumbnails, search, and a live preview beside it, or press Space for Quick Look.",
            keywords: ["open", "browse", "look inside", "quick look", "space", "thumbnails", "search", "preview"]),
        Topic(
            anchor: "edit", title: "Adding, Renaming, & Deleting Files",
            summary:
                "Drop files and folders onto any folder, paste, press ⌘⇧A to add files, or press ⌘⇧N for a new folder. Hovering a dragged item over a collapsed folder for 0.7 seconds springs it open. Press Return to rename, Delete to remove, and ⌘Z to undo any change.",
            keywords: ["add", "change", "rename", "delete", "new folder", "undo", "redo", "drag", "spring", "paste"]),
        Topic(
            anchor: "inplace", title: "Editing Files in Place",
            summary:
                "Double-click any file inside an archive to open it in its default app, or choose Open With from the shortcut menu. Save your changes in that app and Zipboy automatically updates the archive.",
            keywords: ["edit in place", "double-click", "open with", "save", "external", "nested"]),
        Topic(
            anchor: "extract", title: "Extracting & Dragging Out",
            summary:
                "Drag any files or folders out to Finder, press ⌘E to extract next to the archive (or to your default destination in Settings), or press ⌥⌘E to choose a destination folder. A single folder extracts as itself, never wrapped inside an extra folder.",
            keywords: ["extract", "take out", "unpack", "finder", "drag out", "destination", "wrap"]),
        Topic(
            anchor: "create", title: "Making a New ZIP Archive",
            summary:
                "Drop files or folders onto the Zipboy icon in the Dock, choose Compress with Zipboy in Finder’s Services menu, or press ⌘N to start an empty archive window and drag items in.",
            keywords: ["make a zip", "create", "new archive", "compress", "dock", "drop"]),
        Topic(
            anchor: "import", title: "Opening RAR, 7z, & Tar Archives",
            summary:
                "RAR, 7z, tar, and other non-ZIP archives open as a new ZIP document named after the original archive. Any edits or saves write to the new ZIP, leaving the original file untouched.",
            keywords: ["rar", "7z", "tar", "import", "read-only", "convert", "original"]),
        Topic(
            anchor: "password", title: "Passwords & AES-256 Encryption",
            summary:
                "Choose File > Set Password… to encrypt the archive with AES-256 when saved, or File > Remove Password to save it unencrypted. Check “Remember password in Keychain” on the password sheet so reopening the archive needs no password prompt.",
            keywords: ["password", "encrypt", "aes", "keychain", "lock", "security", "decrypt"]),
        Topic(
            anchor: "verify", title: "Integrity Verification & Checksums",
            summary:
                "Choose File > Verify Archive (⌘⇧T) or click Verify in the Inspector to test every entry’s integrity without writing files to disk. Select any file to see its CRC-32 and SHA-256 checksums in the right-hand Inspector (⌥⌘I).",
            keywords: ["verify", "checksum", "crc32", "sha256", "integrity", "corrupt", "inspector"]),
        Topic(
            anchor: "export", title: "Exporting & Legacy Filename Encodings",
            summary:
                "Choose File > Export… (⌘⇧E) to write the archive as .zip, .tar.gz, .tar.xz, .tar, or .7z. If an archive created on another system displays garbled filenames, choose View > Text Encoding to re-read names in Shift-JIS, GB18030, Big5, EUC-KR, Windows-1251, Windows-1252, or CP437.",
            keywords: ["export", "tar", "7z", "encoding", "shift-jis", "gb18030", "cp437", "unicode"]),
    ]

    /// The book's identifier, which the app's `CFBundleHelpBookName` must match.
    public static let bookIdentifier = "com.oddurs.zipboy.help"

    /// The help book bundle's Info.plist, for Help Viewer to find the title, first page, and indexes.
    public static func bookInfo(version: String) -> [String: Any] {
        [
            "CFBundleDevelopmentRegion": "en", "CFBundleIdentifier": bookIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "Zipboy", "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": version, "CFBundleSignature": "hbwr", "CFBundleVersion": version,
            "HPDBookAccessPath": "index.html", "HPDBookIndexPath": "Zipboy.helpindex",
            "HPDBookCSIndexPath": "Zipboy.cshelpindex", "HPDBookTitle": "Zipboy Help", "HPDBookType": "3",
        ]
    }

    /// A topic as a help page. The description and keywords are what Help menu search matches.
    public static func page(for topic: Topic) -> String {
        html(
            title: topic.title, description: topic.summary, keywords: topic.keywords,
            body: "<a name=\"\(topic.anchor)\"></a><h1>\(escape(topic.title))</h1><p>\(escape(topic.summary))</p>"
                + "<p class=\"back\"><a href=\"index.html\">All topics</a></p>")
    }

    /// The book's first page: every topic, linked.
    public static func index() -> String {
        let links = all.map { "<li><a href=\"\($0.anchor).html\">\(escape($0.title))</a></li>" }.joined()
        return html(
            title: "Zipboy Help", description: "How to open, change, extract, and protect archives with Zipboy.",
            keywords: [], body: "<h1>Zipboy Help</h1><ul>\(links)</ul>", isIndex: true)
    }

    private static func html(
        title: String, description: String, keywords: [String], body: String, isIndex: Bool = false
    )
        -> String
    {
        """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
        <title>\(escape(title))</title>
        <meta name="description" content="\(escape(description))">
        <meta name="keywords" content="\(escape(keywords.joined(separator: ", ")))">
        \(isIndex ? "<meta name=\"AppleTitle\" content=\"Zipboy Help\">" : "")
        <meta name="robots" content="index, anchors">
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px -apple-system, system-ui, sans-serif; margin: 28px 36px; line-height: 1.45; }
        h1 { font-size: 22px; font-weight: 600; }
        li { margin: 6px 0; }
        .back { margin-top: 24px; }
        </style></head><body>\(body)</body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
