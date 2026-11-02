import Foundation

/// An archive's entries as a preview shows them, read without unpacking anything.
public struct ArchiveListing: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let isDirectory: Bool
        public let modified: Date?

        public init(path: String, size: Int64, isDirectory: Bool, modified: Date?) {
            self.path = path
            self.size = size
            self.isDirectory = isDirectory
            self.modified = modified
        }
    }

    public let format: String
    public let entries: [Entry]
    /// There were more entries than the listing's limit, and only the first are here.
    public let isTruncated: Bool
    /// Some entries are encrypted. Their names may still be readable, as a ZIP's always are.
    public let isEncrypted: Bool
    /// The names themselves are encrypted, so nothing can be listed without the password.
    public let namesHidden: Bool

    public init(format: String, entries: [Entry], isTruncated: Bool, isEncrypted: Bool, namesHidden: Bool) {
        self.format = format
        self.entries = entries
        self.isTruncated = isTruncated
        self.isEncrypted = isEncrypted
        self.namesHidden = namesHidden
    }
}

/// The page Finder's Quick Look shows for an archive: its name, what it holds, and its tree of folders
/// and files with their sizes, drawn in the system's type and colours for either appearance.
public enum ArchivePreview {
    final class Folder {
        let name: String
        var folders: [String: Folder] = [:]
        var files: [(name: String, size: Int64)] = []
        init(_ name: String) { self.name = name }

        var size: Int64 { files.reduce(0) { $0 + $1.size } + folders.values.reduce(0) { $0 + $1.size } }
        var count: Int { files.count + folders.values.reduce(0) { $0 + 1 + $1.count } }

        func folder(_ path: [Substring]) -> Folder {
            guard let first = path.first else { return self }
            let child = folders[String(first)] ?? Folder(String(first))
            folders[String(first)] = child
            return child.folder(Array(path.dropFirst()))
        }
    }

    /// Folders implied by a path but missing from the archive's own entries still appear, as they do
    /// when the archive is unpacked.
    static func tree(_ entries: [ArchiveListing.Entry]) -> Folder {
        let root = Folder("")
        for entry in entries {
            let parts = entry.path.split(separator: "/")
            guard let last = parts.last else { continue }
            if entry.isDirectory {
                _ = root.folder(parts)
            } else {
                root.folder(Array(parts.dropLast())).files.append((String(last), entry.size))
            }
        }
        return root
    }

    public static func html(for listing: ArchiveListing, name: String, fileSize: Int64?) -> String {
        let root = tree(listing.entries)
        var facts = ["\(listing.format) archive"]
        if !listing.namesHidden {
            let count = root.count
            facts.append(count == 1 ? "1 item" : "\(count.formatted()) items")
            facts.append("\(size(root.size)) unpacked")
        }
        if let fileSize { facts.append("\(size(fileSize)) on disk") }

        var body = ""
        if listing.namesHidden {
            body = notice("lock", "The names in this archive are encrypted. Open it in Zipboy to enter the password.")
        } else if root.count == 0 {
            body = notice("", "This archive is empty.")
        } else {
            // Most archives wrap everything in one folder; opening it saves the first click, as the app does.
            body = "<ul class=\"tree\">\(rows(root, open: root.folders.count == 1 && root.files.isEmpty))</ul>"
            if listing.isTruncated {
                body += notice("", "Only the first \(listing.entries.count.formatted()) items are shown.")
            }
        }
        let lock = listing.isEncrypted && !listing.namesHidden ? "<span class=\"lock\">\(glyph("lock"))</span>" : ""
        return """
            <!DOCTYPE html><html><head><meta charset="utf-8"><style>\(css)</style></head><body>
            <header><h1>\(escape(name))\(lock)</h1><p>\(escape(facts.joined(separator: " · ")))</p></header>
            \(body)
            </body></html>
            """
    }

    private static func rows(_ folder: Folder, open: Bool) -> String {
        var out = ""
        let folders = folder.folders.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for child in folders {
            // A lone folder inside a lone folder opens too, so a deep wrapper doesn't hide everything.
            let opensNext = open && child.folders.count == 1 && child.files.isEmpty
            out += "<li><details\(open ? " open" : "")><summary>\(row(child.name, size(child.size), glyph("folder")))"
            out += "</summary><ul>\(rows(child, open: opensNext))</ul></details></li>"
        }
        for file in folder.files.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            out += "<li>\(row(file.name, size(file.size), glyph("file")))</li>"
        }
        return out
    }

    private static func row(_ name: String, _ size: String, _ icon: String) -> String {
        "<span class=\"row\">\(icon)<span class=\"name\">\(escape(name))</span><span class=\"size\">\(size)</span></span>"
    }

    private static func notice(_ icon: String, _ text: String) -> String {
        "<p class=\"notice\">\(icon.isEmpty ? "" : glyph(icon))\(escape(text))</p>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Small outline glyphs in the manner of SF Symbols, inline so the page needs nothing from outside.
    private static func glyph(_ name: String) -> String {
        let paths =
            switch name {
            case "folder":
                "<path class=\"folder\" d=\"M1.5 4.5a1.5 1.5 0 0 1 1.5-1.5h3l1.5 1.5H13a1.5 1.5 0 0 1 1.5 1.5v6A1.5 1.5 0 0 1 13 13.5H3A1.5 1.5 0 0 1 1.5 12z\"/>"
            case "lock":
                "<path d=\"M4.5 7.5V5.5a3.5 3.5 0 0 1 7 0v2M3.5 7.5h9v6h-9z\"/>"
            default:
                "<path d=\"M3.5 1.5h6l3 3v10h-9zM9.5 1.5v3h3\"/>"
            }
        return "<svg class=\"glyph\" viewBox=\"0 0 16 16\" aria-hidden=\"true\">\(paths)</svg>"
    }

    private static let css = """
        :root { color-scheme: light dark; --secondary: rgba(0,0,0,0.5); --rule: rgba(0,0,0,0.1);
          --folder: #1f8ef1; }
        @media (prefers-color-scheme: dark) {
          :root { --secondary: rgba(255,255,255,0.55); --rule: rgba(255,255,255,0.12); --folder: #4aa8ff; } }
        body { font: 13px -apple-system, system-ui, sans-serif; margin: 0; padding: 16px 20px; }
        header { padding-bottom: 10px; margin-bottom: 6px; border-bottom: 1px solid var(--rule); }
        h1 { font-size: 15px; font-weight: 600; margin: 0 0 2px; word-break: break-all; }
        header p, .size, .notice { color: var(--secondary); }
        header p { margin: 0; font-size: 12px; }
        ul { list-style: none; margin: 0; padding: 0; }
        ul ul { padding-left: 18px; }
        summary { list-style: none; cursor: default; }
        summary::-webkit-details-marker { display: none; }
        summary::before { content: "›"; display: inline-block; width: 12px; color: var(--secondary);
          transition: transform 0.1s; }
        details[open] > summary::before { transform: rotate(90deg); }
        li > .row { padding-left: 12px; }
        .row { display: inline-flex; align-items: center; width: calc(100% - 12px); line-height: 22px; }
        .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .size { font-variant-numeric: tabular-nums; padding-left: 12px; }
        .glyph { width: 15px; height: 15px; margin-right: 6px; flex: none; fill: none; stroke: var(--secondary);
          stroke-width: 1.1; vertical-align: -3px; }
        .glyph .folder { fill: var(--folder); stroke: none; }
        .lock .glyph { margin-left: 6px; }
        .notice { margin: 14px 0 0; }
        """
}
