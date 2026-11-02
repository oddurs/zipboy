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
    /// The archive exhibits decompression-bomb or spoofed-size characteristics.
    case suspiciousArchive(String)

    public struct UserExplanation: Equatable, Sendable {
        public let title: String
        public let message: String
        public let technicalDetails: String?

        public init(title: String, message: String, technicalDetails: String? = nil) {
            self.title = title
            self.message = message
            self.technicalDetails = technicalDetails
        }
    }

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
        case .suspiciousArchive(let reason):
            reason
        }
    }

    /// Maps any archive, Cocoa, or POSIX error to a clear human-readable sentence and actionable next step,
    /// keeping raw `libarchive` or POSIX diagnostics in `technicalDetails`.
    public static func describe(_ error: Error, fileName: String? = nil) -> UserExplanation {
        let label = fileName.map { "“\($0)”" } ?? "the archive"
        if let archiveError = error as? ArchiveError {
            switch archiveError {
            case .passwordRequired:
                return UserExplanation(
                    title: "\(label) is protected with a password.",
                    message: "Enter the archive’s password to open or extract its contents."
                )
            case .wrongPassword:
                return UserExplanation(
                    title: "The password for \(label) wasn’t right.",
                    message: "Check the password and try again."
                )
            case .unsupportedEncryption(let format):
                return UserExplanation(
                    title: "\(label) uses unsupported encryption.",
                    message:
                        "It’s an encrypted \(format) archive. Zipboy can open password-protected ZIP archives, but can’t decrypt encrypted \(format) archives yet."
                )
            case .noSpace(let needed, let available):
                return UserExplanation(
                    title: "There isn’t enough free space on the disk.",
                    message:
                        "Working with \(label) needs at least \(size(needed)), and only \(size(available)) is available. Free up disk space and try again."
                )
            case .suspiciousArchive(let reason):
                return UserExplanation(
                    title: "\(label) was stopped for safety.",
                    message: reason
                )
            case .cancelled:
                return UserExplanation(title: "Cancelled.", message: "")
            case .unreadable(let raw):
                return explainRaw(raw, label: label, writing: false)
            case .unwritable(let raw):
                return explainRaw(raw, label: label, writing: true)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileWriteOutOfSpace:
                return UserExplanation(
                    title: "There isn’t enough free space on the disk.",
                    message: "Free up disk space and try saving \(label) again.",
                    technicalDetails: nsError.localizedDescription
                )
            case .fileWriteNoPermission, .fileWriteVolumeReadOnly:
                return UserExplanation(
                    title: "Zipboy doesn’t have permission to save \(label) here.",
                    message:
                        "The file or folder may be locked or read-only. Choose File > Duplicate to save a copy in another folder.",
                    technicalDetails: nsError.localizedDescription
                )
            case .fileReadNoPermission:
                return UserExplanation(
                    title: "Zipboy doesn’t have permission to read \(label).",
                    message: "Check the file’s permissions in Finder’s Get Info window and try again.",
                    technicalDetails: nsError.localizedDescription
                )
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case EACCES, EPERM, EROFS:
                return UserExplanation(
                    title: "Zipboy doesn’t have permission to modify \(label).",
                    message:
                        "The file or folder is read-only. Choose File > Duplicate to save a copy in another folder.",
                    technicalDetails: nsError.localizedDescription
                )
            case ENOSPC:
                return UserExplanation(
                    title: "There isn’t enough free space on the disk.",
                    message: "Free up disk space and try again.",
                    technicalDetails: nsError.localizedDescription
                )
            default:
                break
            }
        }
        return explainRaw(error.localizedDescription, label: label, writing: false)
    }

    private static func explainRaw(_ raw: String, label: String, writing: Bool) -> UserExplanation {
        let lower = raw.lowercased()
        if lower.contains("truncated") || lower.contains("premature end")
            || lower.contains("smaller than 22 bytes") || lower.contains("end of central directory")
        {
            return UserExplanation(
                title: "\(label) appears to be incomplete.",
                message:
                    "The archive ends unexpectedly and may not have finished downloading or copying. Try downloading or copying it again.",
                technicalDetails: raw
            )
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted")
            || lower.contains("read-only file system")
        {
            return UserExplanation(
                title: "Zipboy doesn’t have permission to \(writing ? "save" : "access") \(label).",
                message: writing
                    ? "Choose File > Duplicate to save a copy in a folder you can write to."
                    : "Check the file’s permissions in Finder’s Get Info window and try again.",
                technicalDetails: raw
            )
        }
        if lower.contains("no space left") || lower.contains("out of space") || lower.contains("disk full") {
            return UserExplanation(
                title: "There isn’t enough free space on the disk.",
                message: "Free up some disk space and try again.",
                technicalDetails: raw
            )
        }
        if lower.contains("unsupported") || lower.contains("compression method") {
            return UserExplanation(
                title: "\(label) uses an unsupported archive feature.",
                message:
                    "This archive was created with a compression method or variant that Zipboy doesn’t support yet.",
                technicalDetails: raw
            )
        }
        if lower.contains("unrecognized archive") || lower.contains("damaged") || lower.contains("corrupt")
            || lower.contains("bad crc") || lower.contains("checksum")
        {
            return UserExplanation(
                title: "\(label) is damaged or isn’t a supported archive.",
                message:
                    "The archive’s contents couldn’t be verified. If it was downloaded, try downloading a fresh copy.",
                technicalDetails: raw
            )
        }
        return UserExplanation(
            title: writing ? "\(label) couldn’t be saved." : "\(label) couldn’t be opened.",
            message: writing
                ? "Check that the destination folder is writable and has enough free space."
                : "The file may be damaged or in a format Zipboy doesn’t recognize.",
            technicalDetails: raw
        )
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
        var entryCount = 0
        var expansion = ExpansionGuard(archiveBytes: Int64(total))
        let maxEntries = 250_000
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
            entryCount += 1
            if entryCount > maxEntries {
                throw ArchiveError.suspiciousArchive(
                    "This archive contains more than \(maxEntries.formatted()) items and was stopped to protect against a decompression bomb."
                )
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
                    let sizeSet = archive_entry_size_is_set(entry) != 0
                    let size = archive_entry_size(entry)
                    if sizeSet && size < 0 {
                        throw ArchiveError.suspiciousArchive(
                            "The entry “\(path)” declares a negative file size and cannot be trusted.")
                    }
                    if sizeSet { try expansion.admit(declared: size, path: path) }
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
                                    let before = archive_filter_bytes(a, -1)
                                    try Deflate64.extract(
                                        named: raw, occurrence: occ, from: archive, to: out,
                                        budget: &budget, capacity: capacity, report: report,
                                        admit: { bytes, consumed in
                                            try expansion.add(bytes, consumed: before + Int64(consumed))
                                        })
                                    break
                                }
                                if encrypted { throw ArchiveError.wrongPassword }
                                throw ArchiveError.unreadable(message(a))
                            }
                            let chunkBytes = Int64(n)
                            if sizeSet, size > 0, !isXar(a), written + chunkBytes > size {
                                throw ArchiveError.suspiciousArchive(
                                    "The entry “\(path)” expanded past its declared size and was stopped."
                                )
                            }
                            try expansion.add(chunkBytes, consumed: archive_filter_bytes(a, -1))
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

    /// Tells a decompression bomb from a file that merely compresses well. Ratio alone can't: Deflate
    /// makes about 1,030:1 of zeros, so a blank disk image looks exactly like a bomb's payload, and a
    /// flat 1,000:1 limit both refused that image and let through any bomb with a little noise in it.
    /// What separates them is how much they cost, so the guard counts the bytes written.
    struct ExpansionGuard {
        /// Up to this much output, no ratio is refused. It is the most item 0041 lets a bomb cost, and
        /// far above what people really zip at extreme ratios: blank disk images, zeroed swap, sparse
        /// databases. Free space is still checked against every declared size below it.
        static let floor: Int64 = 1_000_000_000
        /// Past the floor, more than this many bytes out for each byte in is a bomb. Text and logs
        /// compress 3–20:1 and rarely pass 50:1 even under xz, so real data a gigabyte and up stays
        /// well under it, while a bomb is built to sit near its format's ceiling (1,030:1 for Deflate,
        /// far more for bzip2 and xz).
        static let ratio: Int64 = 100

        let archiveBytes: Int64
        private(set) var expanded: Int64 = 0

        init(archiveBytes: Int64) {
            self.archiveBytes = max(archiveBytes, 1)
        }

        /// Refuses, before anything is written, an entry whose declared size the whole archive couldn't
        /// produce within the ratio: no placement of its compressed bytes makes that honest.
        func admit(declared: Int64, path: String) throws {
            let (after, overflow) = expanded.addingReportingOverflow(declared)
            guard overflow || (after > Self.floor && after / archiveBytes > Self.ratio) else { return }
            throw ArchiveError.suspiciousArchive(
                "The entry “\(path)” would expand to more than \(Self.ratio)× the archive’s size and was stopped to protect against a decompression bomb."
            )
        }

        /// Counts `bytes` about to be written, `consumed` being the compressed bytes read so far. The
        /// running ratio catches a bomb whose declared sizes hide behind padding later in the file.
        mutating func add(_ bytes: Int64, consumed: Int64) throws {
            let after = expanded + bytes
            if after > Self.floor, after / max(consumed, 1) > Self.ratio {
                throw ArchiveError.suspiciousArchive(
                    "This archive expanded past \(ByteCountFormatter.string(fromByteCount: Self.floor, countStyle: .file)) at more than \(Self.ratio)× its compressed size and was stopped to protect against a decompression bomb."
                )
            }
            expanded = after
        }
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
                            // Verifying writes nothing, so there is no disk for a bomb to fill.
                            try Deflate64.extract(
                                named: raw, occurrence: occ, from: archive, to: devNull,
                                budget: &budget, capacity: { nil }, report: report, admit: { _, _ in })
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
