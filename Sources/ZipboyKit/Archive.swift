import CArchive
import Foundation

public enum ArchiveError: LocalizedError, Equatable {
    case passwordRequired
    case wrongPassword
    case unreadable(String)
    case unwritable(String)
    case cancelled
    /// The next entry needs `needed` bytes and the volume has `available`.
    case noSpace(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .passwordRequired: "This archive is protected with a password."
        case .wrongPassword: "The password is incorrect."
        case .unreadable(let why): "The archive couldn’t be read. \(why)"
        case .unwritable(let why): "The archive couldn’t be written. \(why)"
        case .cancelled: "Cancelled."
        case .noSpace(let needed, let available):
            "There isn’t enough space on the disk. It needs at least \(Self.size(needed)), and \(Self.size(available)) is free."
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct ExtractSummary: Equatable, Sendable {
    /// libarchive's name for the format, such as "ZIP 2.0 (deflation)" or "RAR".
    public var format: String
    public var encrypted: Bool
    /// Entry paths left out because they were unsafe or Finder metadata.
    public var skipped: [String]
}

/// Reads every format libarchive knows and writes ZIP, the one format worth writing back.
public enum Archive {
    private static let chunk = 1 << 20

    /// Unpacks `archive` into the empty directory `root`. Entries that would land outside `root`, through
    /// `..`, an absolute path, or a symlink, are skipped rather than trusted. `progress` hears the share of
    /// the file read so far, from 0 to 1, and stops the work by returning false. Each file is checked
    /// against `capacity`, the free bytes on `root`'s volume, before it is written, so a full disk stops
    /// the work cleanly instead of partway through a file.
    public static func extract(
        _ archive: URL, into root: URL, password: String? = nil, progress: ((Double) -> Bool)? = nil,
        capacity: (() -> Int64?)? = nil
    ) throws -> ExtractSummary {
        let capacity = capacity ?? { freeSpace(on: root) }
        useUTF8Names()
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        if let password { archive_read_add_passphrase(a, password) }
        guard archive_read_open_filename(a, archive.path, chunk) == ARCHIVE_OK else {
            throw ArchiveError.unreadable(message(a))
        }

        let total = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        func report() throws {
            guard let progress, total > 0 else { return }
            guard progress(min(1, Double(archive_filter_bytes(a, -1)) / total)) else { throw ArchiveError.cancelled }
        }

        // Asking the volume is slow-ish, so ask once and count down, and ask again only when a file
        // might not fit.
        var budget = capacity()
        var summary = ExtractSummary(format: "", encrypted: false, skipped: [])
        var folders: [(URL, Date)] = []
        let fm = FileManager.default
        var buffer = [UInt8](repeating: 0, count: chunk)
        var entry: OpaquePointer?

        while true {
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else {
                // A RAR or 7z whose headers are encrypted fails here, before any entry is seen.
                if let password, !password.isEmpty, isPasswordProblem(a) { throw ArchiveError.wrongPassword }
                if isPasswordProblem(a) { throw ArchiveError.passwordRequired }
                throw ArchiveError.unreadable(message(a))
            }
            if summary.format.isEmpty, let name = archive_format_name(a) { summary.format = String(cString: name) }
            try report()
            let encrypted = archive_entry_is_encrypted(entry) != 0
            summary.encrypted = summary.encrypted || encrypted
            if encrypted && password == nil { throw ArchiveError.passwordRequired }

            let raw = string(archive_entry_pathname_utf8(entry)) ?? string(archive_entry_pathname(entry)) ?? ""
            guard let path = EntryPath.sanitized(raw), !hasLinkAbove(path, in: root) else {
                summary.skipped.append(raw)
                archive_read_data_skip(a)
                continue
            }
            let url = root.appendingPathComponent(path)
            let perm = Int(archive_entry_perm(entry)) & 0o777
            let modified =
                archive_entry_mtime_is_set(entry) != 0
                ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil

            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch Int32(archive_entry_filetype(entry)) {
                case AE_IFDIR:
                    if !isDirectory(url) {
                        try? fm.removeItem(at: url)
                        try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    }
                    try fm.setAttributes([.posixPermissions: perm | 0o700], ofItemAtPath: url.path)
                    if let modified { folders.append((url, modified)) }
                case AE_IFLNK:
                    let target =
                        string(archive_entry_symlink_utf8(entry)) ?? string(archive_entry_symlink(entry)) ?? ""
                    guard EntryPath.linkStaysInside(path: path, target: target) else {
                        summary.skipped.append(raw)
                        continue
                    }
                    try? fm.removeItem(at: url)
                    try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
                case AE_IFREG:
                    let size = archive_entry_size(entry)
                    if let known = budget, size > known {
                        let fresh = capacity() ?? known
                        budget = fresh
                        if size > fresh { throw ArchiveError.noSpace(needed: size, available: fresh) }
                    }
                    try? fm.removeItem(at: url)
                    guard fm.createFile(atPath: url.path, contents: nil) else {
                        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
                    }
                    let out = try FileHandle(forWritingTo: url)
                    defer { try? out.close() }
                    while true {
                        let n = archive_read_data(a, &buffer, buffer.count)
                        if n == 0 { break }
                        guard n > 0 else {
                            if encrypted { throw ArchiveError.wrongPassword }
                            throw ArchiveError.unreadable(message(a))
                        }
                        do {
                            try out.write(contentsOf: buffer[0..<n])
                        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
                            // A size the archive didn't declare, or space taken meanwhile by something else.
                            try? out.close()
                            try? fm.removeItem(at: url)
                            throw ArchiveError.noSpace(needed: size, available: capacity() ?? 0)
                        }
                        budget = budget.map { $0 - Int64(n) }
                        try report()
                    }
                    var attributes: [FileAttributeKey: Any] = [.posixPermissions: perm | 0o600]
                    if let modified { attributes[.modificationDate] = modified }
                    try fm.setAttributes(attributes, ofItemAtPath: url.path)
                default:
                    // Devices, FIFOs, and sockets mean nothing outside the machine that made them.
                    summary.skipped.append(raw)
                    archive_read_data_skip(a)
                }
            } catch let error as ArchiveError {
                throw error
            } catch {
                throw ArchiveError.unreadable(error.localizedDescription)
            }
        }
        // Last, because writing a folder's contents moves its date.
        for (url, date) in folders.reversed() {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return summary
    }

    /// Zips the contents of `root` into a new file at `destination`, leaving out Finder metadata. With a
    /// password, every entry is encrypted with AES-256. `progress` hears the share of bytes written, from
    /// 0 to 1, and stops the work by returning false.
    public static func writeZip(
        from root: URL, to destination: URL, password: String? = nil, progress: ((Double) -> Bool)? = nil
    ) throws {
        useUTF8Names()
        guard let a = archive_write_new() else { throw ArchiveError.unwritable("Out of memory.") }
        defer { archive_write_free(a) }
        archive_write_set_format_zip(a)
        if let password, !password.isEmpty {
            guard archive_write_set_options(a, "zip:encryption=aes256") == ARCHIVE_OK,
                archive_write_set_passphrase(a, password) == ARCHIVE_OK
            else { throw ArchiveError.unwritable(message(a)) }
        }
        guard archive_write_open_filename(a, destination.path) == ARCHIVE_OK else {
            throw ArchiveError.unwritable(message(a))
        }

        let fm = FileManager.default
        let items = try contents(of: root).map { path in
            (path, try fm.attributesOfItem(atPath: root.appendingPathComponent(path).path))
        }
        let total = items.reduce(0) {
            $0 + ($1.1[.type] as? FileAttributeType == .typeRegular ? $1.1[.size] as? Int ?? 0 : 0)
        }
        var written = 0
        func report() throws {
            guard let progress else { return }
            guard progress(total == 0 ? 1 : Double(written) / Double(total)) else { throw ArchiveError.cancelled }
        }

        for (path, attributes) in items {
            let url = root.appendingPathComponent(path)
            guard let entry = archive_entry_new() else { throw ArchiveError.unwritable("Out of memory.") }
            defer { archive_entry_free(entry) }
            // Other systems expect composed Unicode; APFS hands back whatever form the name was made in. The
            // locale-encoded setter, because Apple's libarchive decomposes names given to the UTF-8 one.
            archive_entry_set_pathname(entry, path.precomposedStringWithCanonicalMapping)
            archive_entry_set_perm(entry, mode_t((attributes[.posixPermissions] as? Int) ?? 0o644))
            if let date = attributes[.modificationDate] as? Date {
                archive_entry_set_mtime(entry, time_t(date.timeIntervalSince1970), 0)
            }

            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory?:
                archive_entry_set_filetype(entry, UInt32(AE_IFDIR))
                try check(archive_write_header(a, entry), a)
            case .typeSymbolicLink?:
                archive_entry_set_filetype(entry, UInt32(AE_IFLNK))
                archive_entry_set_symlink(entry, try fm.destinationOfSymbolicLink(atPath: url.path))
                try check(archive_write_header(a, entry), a)
            case .typeRegular?:
                archive_entry_set_filetype(entry, UInt32(AE_IFREG))
                archive_entry_set_size(entry, Int64((attributes[.size] as? Int) ?? 0))
                switch ZipMethod.forFile(named: url.lastPathComponent) {
                case .store: archive_write_zip_set_compression_store(a)
                case .deflate: archive_write_zip_set_compression_deflate(a)
                }
                try check(archive_write_header(a, entry), a)
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                while let data = try input.read(upToCount: chunk), !data.isEmpty {
                    let count = data.withUnsafeBytes { archive_write_data(a, $0.baseAddress, $0.count) }
                    guard count == data.count else { throw ArchiveError.unwritable(message(a)) }
                    written += count
                    try report()
                }
            default:
                continue
            }
            try check(archive_write_finish_entry(a), a)
        }
        try check(archive_write_close(a), a)
    }

    /// Every path under `root`, relative and sorted so parents come before children, without Finder
    /// metadata.
    public static func contents(of root: URL) throws -> [String] {
        var paths: [String] = []
        func walk(_ relative: String) throws {
            let dir = relative.isEmpty ? root : root.appendingPathComponent(relative)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            where !EntryPath.isJunk(name) {
                let path = relative.isEmpty ? name : "\(relative)/\(name)"
                paths.append(path)
                if isDirectory(root.appendingPathComponent(path)) { try walk(path) }
            }
        }
        try walk("")
        return paths
    }

    static func freeSpace(on url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    private static func check(_ status: Int32, _ a: OpaquePointer) throws {
        guard status >= ARCHIVE_WARN else { throw ArchiveError.unwritable(message(a)) }
    }

    /// A real folder, not a symlink to one.
    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// Whether a folder on the way to `path` is a symlink. A link that stays inside on its own can still
    /// be stacked with another to climb out, so nothing is written through one.
    private static func hasLinkAbove(_ path: String, in root: URL) -> Bool {
        var url = root
        for part in path.split(separator: "/").dropLast() {
            url.appendPathComponent(String(part))
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    private static func isPasswordProblem(_ a: OpaquePointer) -> Bool {
        let text = message(a).lowercased()
        return text.contains("passphrase") || text.contains("encrypt") || text.contains("password")
    }

    private static func message(_ a: OpaquePointer) -> String {
        string(archive_error_string(a)) ?? "Unknown error."
    }

    private static func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    /// libarchive converts names through the C locale, which starts out as ASCII-only "C" and would turn
    /// every non-ASCII name into an error.
    private static func useUTF8Names() {
        _ = utf8Locale
    }
    private static let utf8Locale: Void = { _ = setlocale(LC_CTYPE, "UTF-8") }()
}
