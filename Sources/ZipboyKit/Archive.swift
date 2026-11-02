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
    /// The archive is encrypted in a way libarchive can't decrypt, whatever the password.
    case unsupportedEncryption(format: String)

    public var errorDescription: String? {
        switch self {
        case .passwordRequired: "This archive is protected with a password."
        case .wrongPassword: "The password is incorrect."
        case .unreadable(let why): "The archive couldn’t be read. \(why)"
        case .unwritable(let why): "The archive couldn’t be written. \(why)"
        case .cancelled: "Cancelled."
        case .unsupportedEncryption(let format):
            "It’s an encrypted \(format) archive, and Zipboy can’t decrypt those yet."
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

public struct VerificationReport: Equatable, Sendable {
    public var format: String
    public var encrypted: Bool
    public var entryCount: Int
    public var totalBytes: Int64
    public var skipped: [String]
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case zip
    case tarGz
    case tarXz
    case tar
    case sevenZip

    public var title: String {
        switch self {
        case .zip: "ZIP (.zip)"
        case .tarGz: "TAR Gzip (.tar.gz)"
        case .tarXz: "TAR XZ (.tar.xz)"
        case .tar: "TAR (.tar)"
        case .sevenZip: "7-Zip (.7z)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .tarGz: "tar.gz"
        case .tarXz: "tar.xz"
        case .tar: "tar"
        case .sevenZip: "7z"
        }
    }
}

/// Reads every format libarchive knows (plus Deflate64 ZIPs) and writes ZIP, the one format worth
/// writing back.
public enum Archive {
    private static let chunk = 1 << 20

    private static let formats: [@Sendable (OpaquePointer) -> Int32] = [
        archive_read_support_format_7zip, archive_read_support_format_ar, archive_read_support_format_cab,
        archive_read_support_format_cpio, archive_read_support_format_empty, archive_read_support_format_iso9660,
        archive_read_support_format_lha, archive_read_support_format_rar, archive_read_support_format_rar5,
        archive_read_support_format_tar, archive_read_support_format_xar, archive_read_support_format_zip,
    ]

    /// Unpacks `archive` into the empty directory `root`. Entries that would land outside `root`, through
    /// `..`, an absolute path, or a symlink, are skipped rather than trusted. `progress` hears the share of
    /// the file read so far, from 0 to 1, and stops the work by returning false. Each file and chunk is
    /// checked against `capacity`, the free bytes on `root`'s volume, before it is written, so a full disk
    /// or decompression bomb stops the work cleanly instead of partway through a file.
    public static func extract(
        _ archive: URL, into root: URL, password: String? = nil,
        encoding: TextEncoding = .auto,
        progress: ((Double) -> Bool)? = nil,
        capacity: (() -> Int64?)? = nil
    ) throws -> ExtractSummary {
        let capacity = capacity ?? { freeSpace(on: root) }
        useUTF8Names()
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        // Container formats only. "All" would include mtree, a text format for describing file trees,
        // which claims plain text files as archives of empty entries.
        for support in formats { _ = support(a) }
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
        // or chunk might not fit.
        var budget = capacity()
        func reserve(_ bytes: Int64, needed: Int64) throws {
            if let known = budget, bytes > known {
                let fresh = capacity() ?? known
                budget = fresh
                if bytes > fresh { throw ArchiveError.noSpace(needed: max(bytes, needed), available: fresh) }
            }
        }

        var summary = ExtractSummary(format: "", encrypted: false, skipped: [])
        var folders: [(URL, Date)] = []
        var deflate64Seen: [String: Int] = [:]
        let fm = FileManager.default
        var buffer = [UInt8](repeating: 0, count: chunk)
        var entry: OpaquePointer?

        while true {
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else {
                // A RAR or 7z whose headers are encrypted fails here, before any entry is seen.
                if isPasswordProblem(a), !canDecrypt(a) {
                    throw ArchiveError.unsupportedEncryption(format: formatName(a))
                }
                if let password, !password.isEmpty, isPasswordProblem(a) { throw ArchiveError.wrongPassword }
                if isPasswordProblem(a) { throw ArchiveError.passwordRequired }
                throw ArchiveError.unreadable(message(a))
            }
            if summary.format.isEmpty, let name = archive_format_name(a) { summary.format = String(cString: name) }
            try report()
            let encrypted = archive_entry_is_encrypted(entry) != 0
            summary.encrypted = summary.encrypted || encrypted
            // Asking for a password libarchive can't use would loop: every answer fails.
            if encrypted, !canDecrypt(a) {
                throw ArchiveError.unsupportedEncryption(format: formatName(a))
            }
            if encrypted && password == nil { throw ArchiveError.passwordRequired }

            let raw = name(of: entry, in: a, encoding: encoding)
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

                // Hardlinks in tar, cpio, 7z, and RAR carry no data stream of their own; they point to an
                // earlier entry in the archive. Copy that entry if it stays safely inside the root.
                if let rawTarget = string(archive_entry_hardlink_utf8(entry)) ?? string(archive_entry_hardlink(entry)),
                    !rawTarget.isEmpty
                {
                    guard let targetPath = EntryPath.sanitized(rawTarget), !hasLinkAbove(targetPath, in: root) else {
                        summary.skipped.append(raw)
                        archive_read_data_skip(a)
                        continue
                    }
                    let targetURL = root.appendingPathComponent(targetPath)
                    guard fm.fileExists(atPath: targetURL.path), !isDirectory(targetURL),
                        (try? targetURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
                    else {
                        summary.skipped.append(raw)
                        archive_read_data_skip(a)
                        continue
                    }
                    let targetSize = Int64((try? fm.attributesOfItem(atPath: targetURL.path)[.size] as? Int) ?? 0)
                    try reserve(targetSize, needed: targetSize)
                    try? fm.removeItem(at: url)
                    try fm.copyItem(at: targetURL, to: url)
                    budget = budget.map { $0 - targetSize }
                    var attributes: [FileAttributeKey: Any] = [.posixPermissions: (perm != 0 ? perm : 0o644) | 0o600]
                    if let modified { attributes[.modificationDate] = modified }
                    try fm.setAttributes(attributes, ofItemAtPath: url.path)
                    continue
                }

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
                    if size > 0 { try reserve(size, needed: size) }
                    try? fm.removeItem(at: url)
                    guard fm.createFile(atPath: url.path, contents: nil) else {
                        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
                    }
                    do {
                        let out = try FileHandle(forWritingTo: url)
                        defer { try? out.close() }
                        var written: Int64 = 0
                        while true {
                            // libarchive's XAR reader leaves the cumulative heap offset in its EOF block,
                            // which makes archive_read_data append bogus NUL padding if read past `size`.
                            let limit =
                                isXar(a) && size >= 0
                                ? Int(min(Int64(buffer.count), max(0, size - written))) : buffer.count
                            if limit == 0 { break }
                            let n = archive_read_data(a, &buffer, limit)
                            if n == 0 { break }
                            if n < 0 {
                                if !encrypted, isZip(a), written == 0, isDeflate64Problem(a) {
                                    let occ = deflate64Seen[raw, default: 0]
                                    deflate64Seen[raw] = occ + 1
                                    try Deflate64.extract(
                                        named: raw, occurrence: occ, from: archive, to: out,
                                        budget: &budget, capacity: capacity, report: report)
                                    break
                                }
                                if encrypted { throw ArchiveError.wrongPassword }
                                throw ArchiveError.unreadable(message(a))
                            }
                            let chunkBytes = Int64(n)
                            try reserve(chunkBytes, needed: max(size, written + chunkBytes))
                            do {
                                try out.write(contentsOf: buffer[0..<n])
                            } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
                                // A size the archive didn't declare, or space taken meanwhile by something else.
                                throw ArchiveError.noSpace(
                                    needed: max(size, written + chunkBytes), available: capacity() ?? 0)
                            }
                            written += chunkBytes
                            budget = budget.map { $0 - chunkBytes }
                            try report()
                        }
                    } catch {
                        try? fm.removeItem(at: url)
                        throw error
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

    /// Zips the contents of `root` into `destination`, leaving out Finder metadata. Writes to a sibling
    /// staging file, flushes it to disk, and renames it into place so a failure or cancellation never
    /// leaves a half-written archive behind. With a password, every entry is encrypted with AES-256.
    /// `progress` hears the share of bytes written, from 0 to 1, and stops the work by returning false.
    public static func writeZip(
        from root: URL, to destination: URL, password: String? = nil,
        compressionLevel: Settings.CompressionLevel = .balanced,
        progress: ((Double) -> Bool)? = nil
    ) throws {
        useUTF8Names()
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".Zipboy-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: staging) }

        try writeZipFile(
            from: root, to: staging, password: password, compressionLevel: compressionLevel, progress: progress)

        let fd = open(staging.path, O_RDONLY)
        if fd >= 0 {
            _ = fsync(fd)
            close(fd)
        }
        guard rename(staging.path, destination.path) == 0 else {
            let reason = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO).localizedDescription
            throw ArchiveError.unwritable(reason)
        }
    }

    private static func writeZipFile(
        from root: URL, to staging: URL, password: String?,
        compressionLevel: Settings.CompressionLevel,
        progress: ((Double) -> Bool)?
    ) throws {
        guard let a = archive_write_new() else { throw ArchiveError.unwritable("Out of memory.") }
        defer { archive_write_free(a) }
        archive_write_set_format_zip(a)
        guard archive_write_set_options(a, "zip:compression-level=\(compressionLevel.rawValue)") == ARCHIVE_OK else {
            throw ArchiveError.unwritable(message(a))
        }
        if let password, !password.isEmpty {
            guard archive_write_set_options(a, "zip:encryption=aes256") == ARCHIVE_OK,
                archive_write_set_passphrase(a, password) == ARCHIVE_OK
            else { throw ArchiveError.unwritable(message(a)) }
        }
        guard archive_write_open_filename(a, staging.path) == ARCHIVE_OK else {
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

        var usingStore = false
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
                case .store:
                    if !usingStore {
                        archive_write_zip_set_compression_store(a)
                        usingStore = true
                    }
                case .deflate:
                    if usingStore {
                        archive_write_zip_set_compression_deflate(a)
                        usingStore = false
                    }
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

    /// Streams every entry in `archive` through decompression and integrity verification without
    /// writing any files to disk. Throws an `ArchiveError` if any entry is unreadable or corrupted.
    public static func verify(
        _ archive: URL,
        password: String? = nil,
        encoding: TextEncoding = .auto,
        progress: ((Double) -> Bool)? = nil
    ) throws -> VerificationReport {
        useUTF8Names()
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        for support in formats { _ = support(a) }
        if let password { archive_read_add_passphrase(a, password) }
        guard archive_read_open_filename(a, archive.path, chunk) == ARCHIVE_OK else {
            throw ArchiveError.unreadable(message(a))
        }

        let total = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        func report() throws {
            guard let progress, total > 0 else { return }
            guard progress(min(1, Double(archive_filter_bytes(a, -1)) / total)) else {
                throw ArchiveError.cancelled
            }
        }

        var verification = VerificationReport(
            format: "", encrypted: false, entryCount: 0, totalBytes: 0, skipped: [])
        var deflate64Seen: [String: Int] = [:]
        var buffer = [UInt8](repeating: 0, count: chunk)
        var entry: OpaquePointer?

        while true {
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else {
                if isPasswordProblem(a), !canDecrypt(a) {
                    throw ArchiveError.unsupportedEncryption(format: formatName(a))
                }
                if let password, !password.isEmpty, isPasswordProblem(a) { throw ArchiveError.wrongPassword }
                if isPasswordProblem(a) { throw ArchiveError.passwordRequired }
                throw ArchiveError.unreadable(message(a))
            }
            if verification.format.isEmpty, let name = archive_format_name(a) {
                verification.format = String(cString: name)
            }
            try report()
            let encrypted = archive_entry_is_encrypted(entry) != 0
            verification.encrypted = verification.encrypted || encrypted
            if encrypted, !canDecrypt(a) {
                throw ArchiveError.unsupportedEncryption(format: formatName(a))
            }
            if encrypted && password == nil { throw ArchiveError.passwordRequired }

            let raw = name(of: entry, in: a, encoding: encoding)
            guard let path = EntryPath.sanitized(raw) else {
                verification.skipped.append(raw)
                archive_read_data_skip(a)
                continue
            }

            switch Int32(archive_entry_filetype(entry)) {
            case AE_IFDIR:
                verification.entryCount += 1
            case AE_IFLNK:
                let target =
                    string(archive_entry_symlink_utf8(entry)) ?? string(archive_entry_symlink(entry)) ?? ""
                guard EntryPath.linkStaysInside(path: path, target: target) else {
                    verification.skipped.append(raw)
                    continue
                }
                verification.entryCount += 1
            case AE_IFREG:
                let size = archive_entry_size(entry)
                var readBytes: Int64 = 0
                while true {
                    let limit =
                        isXar(a) && size >= 0
                        ? Int(min(Int64(buffer.count), max(0, size - readBytes))) : buffer.count
                    if limit == 0 { break }
                    let n = archive_read_data(a, &buffer, limit)
                    if n == 0 { break }
                    if n < 0 {
                        if !encrypted, isZip(a), readBytes == 0, isDeflate64Problem(a) {
                            let occ = deflate64Seen[raw, default: 0]
                            deflate64Seen[raw] = occ + 1
                            let devNull = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
                            defer { try? devNull.close() }
                            var budget: Int64? = nil
                            try Deflate64.extract(
                                named: raw, occurrence: occ, from: archive, to: devNull,
                                budget: &budget, capacity: { nil }, report: report)
                            readBytes = max(0, size)
                            break
                        }
                        if encrypted { throw ArchiveError.wrongPassword }
                        throw ArchiveError.unreadable(message(a))
                    }
                    readBytes += Int64(n)
                    try report()
                }
                verification.entryCount += 1
                verification.totalBytes += readBytes
            default:
                verification.skipped.append(raw)
                archive_read_data_skip(a)
            }
        }
        return verification
    }

    /// Exports the contents of `root` to `destination` in the requested `format` (`.zip`, `.tar.gz`,
    /// `.tar.xz`, `.tar`, or `.7z`) atomically via a staging file.
    public static func export(
        from root: URL,
        to destination: URL,
        format: ExportFormat,
        compressionLevel: Settings.CompressionLevel = .balanced,
        password: String? = nil,
        progress: ((Double) -> Bool)? = nil
    ) throws {
        if format == .zip {
            try writeZip(
                from: root, to: destination, password: password,
                compressionLevel: compressionLevel, progress: progress)
            return
        }
        useUTF8Names()
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".Zipboy-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? fm.removeItem(at: staging) }

        guard let a = archive_write_new() else { throw ArchiveError.unwritable("Out of memory.") }
        defer { archive_write_free(a) }

        switch format {
        case .zip:
            archive_write_set_format_zip(a)
        case .tarGz:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_gzip(a)
            _ = archive_write_set_options(a, "gzip:compression-level=\(compressionLevel.rawValue)")
        case .tarXz:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_xz(a)
            _ = archive_write_set_options(a, "xz:compression-level=\(compressionLevel.rawValue)")
        case .tar:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_none(a)
        case .sevenZip:
            archive_write_set_format_7zip(a)
            _ = archive_write_set_options(a, "7zip:compression-level=\(compressionLevel.rawValue)")
        }

        guard archive_write_open_filename(a, staging.path) == ARCHIVE_OK else {
            throw ArchiveError.unwritable(message(a))
        }

        let items = try contents(of: root).map { path in
            (path, try fm.attributesOfItem(atPath: root.appendingPathComponent(path).path))
        }
        let total = items.reduce(0) {
            $0 + ($1.1[.type] as? FileAttributeType == .typeRegular ? $1.1[.size] as? Int ?? 0 : 0)
        }
        var written = 0
        func report() throws {
            guard let progress else { return }
            guard progress(total == 0 ? 1 : Double(written) / Double(total)) else {
                throw ArchiveError.cancelled
            }
        }

        for (path, attributes) in items {
            let url = root.appendingPathComponent(path)
            guard let entry = archive_entry_new() else { throw ArchiveError.unwritable("Out of memory.") }
            defer { archive_entry_free(entry) }
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

        let fd = open(staging.path, O_RDONLY)
        if fd >= 0 {
            _ = fsync(fd)
            close(fd)
        }
        guard rename(staging.path, destination.path) == 0 else {
            let reason = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO).localizedDescription
            throw ArchiveError.unwritable(reason)
        }
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

    /// Only libarchive's ZIP reader decrypts. Its "encryption" capability flags say only that a reader
    /// can tell an entry is encrypted, which the 7z and RAR readers can, so they can't decide this.
    private static func canDecrypt(_ a: OpaquePointer) -> Bool {
        isZip(a)
    }

    private static func isZip(_ a: OpaquePointer) -> Bool {
        archive_format(a) & ARCHIVE_FORMAT_BASE_MASK == ARCHIVE_FORMAT_ZIP
    }

    private static func isXar(_ a: OpaquePointer) -> Bool {
        archive_format(a) & ARCHIVE_FORMAT_BASE_MASK == ARCHIVE_FORMAT_XAR
    }

    private static func isDeflate64Problem(_ a: OpaquePointer) -> Bool {
        let text = message(a).lowercased()
        return text.contains("deflation-64-bit") || text.contains("compression method (9")
    }

    /// libarchive's name for the format, such as "7-Zip" or "RAR5", without the detail in brackets.
    private static func formatName(_ a: OpaquePointer) -> String {
        let name = string(archive_format_name(a)) ?? ""
        let short = name.split(separator: " (").first.map(String.init) ?? name
        return short.isEmpty ? "this kind of" : short
    }

    /// An entry's name as text. ZIPs written without the UTF-8 flag hold either UTF-8, as macOS's own
    /// tools write, or code page 437, as the ZIP specification says and older Windows tools write; bytes
    /// that aren't valid UTF-8 are read as CP437 rather than shown as "".
    private static func name(
        of entry: OpaquePointer, in a: OpaquePointer, encoding: TextEncoding = .auto
    ) -> String {
        if let stored = archive_entry_pathname(entry) {
            let bytes = Data(bytes: stored, count: strlen(stored))
            if encoding != .auto {
                return encoding.decode(bytes)
            }
            if isZip(a) {
                return TextEncoding.auto.decode(bytes)
            }
        }
        if let utf8 = string(archive_entry_pathname_utf8(entry)) {
            return utf8
        }
        if let stored = archive_entry_pathname(entry) {
            let bytes = Data(bytes: stored, count: strlen(stored))
            return encoding.decode(bytes)
        }
        return ""
    }

    static func decodeZipName(_ bytes: Data) -> String {
        TextEncoding.auto.decode(bytes)
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
    /// every non-ASCII name into an error. Also adds Homebrew's tool paths so libarchive's external
    /// decompression filters (such as zstd and lz4) work when the app is launched from Finder.
    private static func useUTF8Names() {
        _ = utf8Locale
    }
    private static let utf8Locale: Void = {
        _ = setlocale(LC_CTYPE, "UTF-8")
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var parts = current.split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !parts.contains(extra) {
            parts.append(extra)
        }
        setenv("PATH", parts.joined(separator: ":"), 1)
    }()
}
