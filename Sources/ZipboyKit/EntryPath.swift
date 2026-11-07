import Foundation

/// The rules for paths inside an archive, kept apart from libarchive so they can be checked as strings.
public enum EntryPath {
    /// Where an entry lands, relative to the extraction root, or nil when it must be skipped: it would
    /// escape the root, or it is Finder metadata nobody wants back.
    public static func sanitized(_ raw: String) -> String? {
        if isAlreadyClean(raw) { return raw }
        // Zips made on Windows often separate with backslashes; no real file name here contains one.
        let parts = raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        var kept: [String] = []
        for part in parts where part != "." {
            if part == ".." { return nil }
            kept.append(part)
        }
        guard !kept.isEmpty, !kept.contains(where: isJunk) else { return nil }
        return kept.joined(separator: "/")
    }

    private static func isAlreadyClean(_ raw: String) -> Bool {
        guard !raw.isEmpty, !raw.hasPrefix("/"), !raw.hasSuffix("/") else { return false }
        let utf8 = raw.utf8
        if utf8.contains(UInt8(ascii: "\\")) { return false }
        var start = utf8.startIndex
        while start < utf8.endIndex {
            let slash = utf8[start...].firstIndex(of: UInt8(ascii: "/")) ?? utf8.endIndex
            let count = utf8.distance(from: start, to: slash)
            if count == 0 { return false }
            let b0 = utf8[start]
            if b0 == UInt8(ascii: ".") {
                if count == 1 { return false }
                let b1 = utf8[utf8.index(after: start)]
                if b1 == UInt8(ascii: "_") { return false }
                if count == 2 && b1 == UInt8(ascii: ".") { return false }
                if count == 9 && raw[start..<slash] == ".DS_Store" { return false }
            } else if count == 8, b0 == UInt8(ascii: "_"), raw[start..<slash] == "__MACOSX" {
                return false
            }
            if slash == utf8.endIndex { break }
            start = utf8.index(after: slash)
        }
        return true
    }

    /// Resource-fork folders, AppleDouble files, and Finder's view settings. They are dropped on the way
    /// in and never written on the way out, so an archive round-trips without growing them.
    public static func isJunk(_ name: String) -> Bool {
        name == "__MACOSX" || name == ".DS_Store" || name.hasPrefix("._")
    }

    /// Whether a symlink stored at `path` with `target` resolves inside the root, read lexically. An
    /// absolute target, or one that climbs above the root, would let a later entry write anywhere.
    public static func linkStaysInside(path: String, target: String) -> Bool {
        guard !target.hasPrefix("/") else { return false }
        var stack = path.split(separator: "/").dropLast().map(String.init)
        for part in target.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                guard !stack.isEmpty else { return false }
                stack.removeLast()
            default: stack.append(String(part))
            }
        }
        return true
    }
}
