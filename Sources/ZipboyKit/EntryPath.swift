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
        var copy = raw
        return copy.withUTF8 { buf -> Bool in
            let n = buf.count
            guard n > 0, let base = buf.baseAddress, base[0] != 0x2F, base[n - 1] != 0x2F else { return false }
            var start = 0
            var i = 0
            while i <= n {
                let b: UInt8 = i < n ? base[i] : 0x2F
                if b == 0x5C { return false }
                if b == 0x2F {
                    let count = i - start
                    if count == 0 { return false }
                    let b0 = base[start]
                    if b0 == 0x2E {
                        if count == 1 { return false }
                        let b1 = base[start + 1]
                        if b1 == 0x5F { return false }
                        if count == 2 && b1 == 0x2E { return false }
                        if count == 9
                            && b1 == 0x44 && base[start + 2] == 0x53 && base[start + 3] == 0x5F
                            && base[start + 4] == 0x53 && base[start + 5] == 0x74 && base[start + 6] == 0x6F
                            && base[start + 7] == 0x72 && base[start + 8] == 0x65
                        {
                            return false
                        }
                    } else if count == 8 && b0 == 0x5F
                        && base[start + 1] == 0x5F && base[start + 2] == 0x4D && base[start + 3] == 0x41
                        && base[start + 4] == 0x43 && base[start + 5] == 0x4F && base[start + 6] == 0x53
                        && base[start + 7] == 0x58
                    {
                        return false
                    }
                    start = i + 1
                }
                i += 1
            }
            return true
        }
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
