import CArchive
import Darwin
import Foundation
import zlib

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
    /// Only ZIP can be written with a password, so exporting an encrypted archive as anything else would
    /// leave it unprotected.
    case cantEncrypt(ExportFormat)
    /// A part of a multi-volume split archive is missing from the folder.
    case missingSplitPiece(String)

    public struct UserExplanation: Equatable, Sendable {
        public let title: String
        public let message: String
        public let technicalDetails: String?
        /// The next step the alert can take for the person, as a button.
        public let recovery: Recovery?

        public init(title: String, message: String, technicalDetails: String? = nil, recovery: Recovery? = nil) {
            self.title = title
            self.message = message
            self.technicalDetails = technicalDetails
            self.recovery = recovery
        }
    }

    /// What an error's alert can do about it.
    public enum Recovery: Equatable, Sendable {
        /// Save a copy somewhere writable: File > Duplicate.
        case duplicate
        /// Open System Settings > General > Storage, to free space.
        case freeSpace
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
        case .cantEncrypt(let format):
            "A .\(format.fileExtension) archive can’t keep a password. Export as ZIP to keep it protected."
        case .missingSplitPiece(let piece):
            "Part of this split archive is missing: “\(piece)”."
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
                        "Working with \(label) needs at least \(size(needed)), and only \(size(available)) is available. Free up disk space and try again.",
                    recovery: .freeSpace
                )
            case .suspiciousArchive(let reason):
                return UserExplanation(
                    title: "\(label) was stopped for safety.",
                    message: reason
                )
            case .cantEncrypt(let format):
                return UserExplanation(
                    title: "A .\(format.fileExtension) archive can’t keep \(label)’s password.",
                    message:
                        "Exporting it as .\(format.fileExtension) would leave its contents unprotected. Choose ZIP to keep the password."
                )
            case .missingSplitPiece(let piece):
                return UserExplanation(
                    title: "\(label) is missing “\(piece)”.",
                    message: "Place all parts of the split archive in the same folder and try again."
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
                    technicalDetails: nsError.localizedDescription, recovery: .freeSpace
                )
            case .fileWriteNoPermission, .fileWriteVolumeReadOnly:
                return UserExplanation(
                    title: "Zipboy doesn’t have permission to save \(label) here.",
                    message: "The file or folder may be locked or read-only. Save a copy in another folder instead.",
                    technicalDetails: nsError.localizedDescription, recovery: .duplicate
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
                    message: "The file or folder is read-only. Save a copy in another folder instead.",
                    technicalDetails: nsError.localizedDescription, recovery: .duplicate
                )
            case ENOSPC:
                return UserExplanation(
                    title: "There isn’t enough free space on the disk.",
                    message: "Free up disk space and try \(label) again.",
                    technicalDetails: nsError.localizedDescription, recovery: .freeSpace
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
                    ? "Save a copy in a folder you can write to instead."
                    : "Check the file’s permissions in Finder’s Get Info window and try again.",
                technicalDetails: raw, recovery: writing ? .duplicate : nil
            )
        }
        if lower.contains("no space left") || lower.contains("out of space") || lower.contains("disk full") {
            return UserExplanation(
                title: "There isn’t enough free space on the disk.",
                message: "Free up some disk space and try \(label) again.",
                technicalDetails: raw, recovery: .freeSpace
            )
        }
        if lower.contains("unsupported") || lower.contains("compression method") {
            // libarchive names the method in brackets, as in "compression method (14: lzma)".
            let method = raw.firstMatch(of: /\((?:\d+: )?([^)]+)\)/).map { String($0.1) }
            return UserExplanation(
                title: "\(label) uses an unsupported archive feature.",
                message: method.map {
                    "It was made with the “\($0)” compression method, which Zipboy can’t read yet. Ask for it in another format, such as a standard ZIP."
                }
                    ?? "It was made with a compression method or variant Zipboy can’t read yet. Ask for it in another format, such as a standard ZIP.",
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

    public struct SplitArchive: Equatable, Sendable {
        public let pieces: [URL]
        public let needsConcatenation: Bool
        public let nextPieceName: String?
    }

    /// Returns true when `url` is a piece of a multi-volume split archive.
    public static func isSplitArchive(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        if filename.wholeMatch(of: /(?i)^.+\.part0*\d+\.rar$/) != nil { return true }
        if filename.wholeMatch(of: /(?i)^.+\.[rz]\d{2,}$/) != nil { return true }
        if filename.wholeMatch(of: /^.+\.\d{3}$/) != nil { return true }
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            let folder = url.deletingLastPathComponent()
            let stem = url.deletingPathExtension().lastPathComponent
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if siblings.contains(where: {
                guard let m = $0.wholeMatch(of: /(?i)^(.+)\.z\d{2,}$/) else { return false }
                return String(m.1).caseInsensitiveCompare(stem) == .orderedSame
            }) {
                return true
            }
            if (splitZipDiskCount(in: url) ?? 0) > 0 { return true }
        } else if ext == "rar" {
            let folder = url.deletingLastPathComponent()
            let stem = url.deletingPathExtension().lastPathComponent
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if siblings.contains(where: {
                guard let m = $0.wholeMatch(of: /(?i)^(.+)\.r\d{2,}$/) else { return false }
                return String(m.1).caseInsensitiveCompare(stem) == .orderedSame
            }) {
                return true
            }
            if isMultiVolumeRAR(url) { return true }
        }
        return false
    }

    /// Resolves all pieces of a split archive in volume order starting from any piece `url`, or returns
    /// `nil` if `url` is a standalone single-file archive. Throws `ArchiveError.missingSplitPiece` naming
    /// the first missing piece if the sequence has a gap or missing volume.
    public static func resolveSplitPieces(for url: URL) throws -> SplitArchive? {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let siblings = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []

        // 1. New RAR naming: <stem>.part1.rar, <stem>.part2.rar (or zero-padded .part01.rar)
        if let match = filename.wholeMatch(of: /(?i)^(.+)\.part(0*(\d+))\.rar$/) {
            let stem = String(match.1)
            let rawDigits = String(match.2)
            let clickedPart = max(1, Int(match.3) ?? 1)
            var found: [Int: (name: String, width: Int)] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /(?i)^(.+)\.part(0*(\d+))\.rar$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.3), n >= 1
                {
                    found[n] = (name: s, width: String(m.2).count)
                }
            }
            let padWidth =
                rawDigits.hasPrefix("0")
                ? rawDigits.count
                : (found.values.first(where: { $0.width > 1 })?.width ?? 1)
            let maxPart = max(clickedPart, found.keys.max() ?? 1, 2)
            var ordered: [URL] = []
            for k in 1...maxPart {
                let expected = String(format: "%@.part%0*d.rar", stem, padWidth, k)
                guard let entry = found[k] else {
                    throw ArchiveError.missingSplitPiece(expected)
                }
                let pieceURL = folder.appendingPathComponent(entry.name)
                guard fm.fileExists(atPath: pieceURL.path) else {
                    throw ArchiveError.missingSplitPiece(entry.name)
                }
                ordered.append(pieceURL)
            }
            let nextName = String(format: "%@.part%0*d.rar", stem, padWidth, maxPart + 1)
            return SplitArchive(pieces: ordered, needsConcatenation: false, nextPieceName: nextName)
        }

        // 2. Old RAR naming: <stem>.rar, <stem>.r00, <stem>.r01, ...
        if let rMatch = filename.wholeMatch(of: /(?i)^(.+)\.r(\d{2,})$/) {
            let stem = String(rMatch.1)
            let width = max(2, String(rMatch.2).count)
            let clickedIdx = max(0, Int(rMatch.2) ?? 0)
            var foundR: [Int: String] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /(?i)^(.+)\.r(\d{2,})$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.2), n >= 0
                {
                    foundR[n] = s
                }
            }
            let rarName = siblings.first { $0.caseInsensitiveCompare("\(stem).rar") == .orderedSame } ?? "\(stem).rar"
            let rarURL = folder.appendingPathComponent(rarName)
            guard fm.fileExists(atPath: rarURL.path) else {
                throw ArchiveError.missingSplitPiece("\(stem).rar")
            }
            let maxIdx = max(clickedIdx, foundR.keys.max() ?? 0)
            var ordered: [URL] = [rarURL]
            for idx in 0...maxIdx {
                let expected = String(format: "%@.r%0*d", stem, width, idx)
                guard let name = foundR[idx] else {
                    throw ArchiveError.missingSplitPiece(expected)
                }
                let pieceURL = folder.appendingPathComponent(name)
                guard fm.fileExists(atPath: pieceURL.path) else {
                    throw ArchiveError.missingSplitPiece(name)
                }
                ordered.append(pieceURL)
            }
            let nextName = String(format: "%@.r%0*d", stem, width, maxIdx + 1)
            return SplitArchive(pieces: ordered, needsConcatenation: false, nextPieceName: nextName)
        } else if ext == "rar" {
            let stem = url.deletingPathExtension().lastPathComponent
            var foundR: [Int: String] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /(?i)^(.+)\.r(\d{2,})$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.2), n >= 0
                {
                    foundR[n] = s
                }
            }
            if !foundR.isEmpty || isMultiVolumeRAR(url) {
                guard fm.fileExists(atPath: url.path) else {
                    throw ArchiveError.missingSplitPiece(filename)
                }
                let maxIdx = max(foundR.keys.max() ?? 0, 0)
                var ordered: [URL] = [url]
                for idx in 0...maxIdx {
                    let expected = String(format: "%@.r%02d", stem, idx)
                    guard let name = foundR[idx] else {
                        throw ArchiveError.missingSplitPiece(expected)
                    }
                    let pieceURL = folder.appendingPathComponent(name)
                    guard fm.fileExists(atPath: pieceURL.path) else {
                        throw ArchiveError.missingSplitPiece(name)
                    }
                    ordered.append(pieceURL)
                }
                let nextName = String(format: "%@.r%02d", stem, maxIdx + 1)
                return SplitArchive(pieces: ordered, needsConcatenation: false, nextPieceName: nextName)
            }
        }

        // 3. Split ZIP naming: <stem>.z01, <stem>.z02, ..., <stem>.zip
        if let zMatch = filename.wholeMatch(of: /(?i)^(.+)\.z(\d{2,})$/) {
            let stem = String(zMatch.1)
            let width = max(2, String(zMatch.2).count)
            let clickedIdx = max(1, Int(zMatch.2) ?? 1)
            var foundZ: [Int: String] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /(?i)^(.+)\.z(\d{2,})$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.2), n >= 1
                {
                    foundZ[n] = s
                }
            }
            let zipName = siblings.first { $0.caseInsensitiveCompare("\(stem).zip") == .orderedSame } ?? "\(stem).zip"
            let zipURL = folder.appendingPathComponent(zipName)
            let eocdDisks = splitZipDiskCount(in: zipURL) ?? 0
            let maxIdx = max(clickedIdx, foundZ.keys.max() ?? 1, eocdDisks, 1)
            var ordered: [URL] = []
            for idx in 1...maxIdx {
                let expected = String(format: "%@.z%0*d", stem, width, idx)
                guard let name = foundZ[idx] else {
                    throw ArchiveError.missingSplitPiece(expected)
                }
                let pieceURL = folder.appendingPathComponent(name)
                guard fm.fileExists(atPath: pieceURL.path) else {
                    throw ArchiveError.missingSplitPiece(name)
                }
                ordered.append(pieceURL)
            }
            guard fm.fileExists(atPath: zipURL.path) else {
                throw ArchiveError.missingSplitPiece(zipName)
            }
            ordered.append(zipURL)
            return SplitArchive(pieces: ordered, needsConcatenation: false, nextPieceName: nil)
        } else if ext == "zip" {
            let stem = url.deletingPathExtension().lastPathComponent
            var foundZ: [Int: String] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /(?i)^(.+)\.z(\d{2,})$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.2), n >= 1
                {
                    foundZ[n] = s
                }
            }
            let eocdDisks = splitZipDiskCount(in: url) ?? 0
            if !foundZ.isEmpty || eocdDisks > 0 {
                let maxIdx = max(foundZ.keys.max() ?? 1, eocdDisks, 1)
                var ordered: [URL] = []
                for idx in 1...maxIdx {
                    let expected = String(format: "%@.z%02d", stem, idx)
                    guard let name = foundZ[idx] else {
                        throw ArchiveError.missingSplitPiece(expected)
                    }
                    let pieceURL = folder.appendingPathComponent(name)
                    guard fm.fileExists(atPath: pieceURL.path) else {
                        throw ArchiveError.missingSplitPiece(name)
                    }
                    ordered.append(pieceURL)
                }
                guard fm.fileExists(atPath: url.path) else {
                    throw ArchiveError.missingSplitPiece(filename)
                }
                ordered.append(url)
                return SplitArchive(pieces: ordered, needsConcatenation: false, nextPieceName: nil)
            }
        }

        // 4. Numbered .001, .002, ... (including .7z.001, .tar.001, .zip.001, etc.)
        if let numMatch = filename.wholeMatch(of: /^(.+)\.(\d{3})$/),
            let clickedIdx = Int(numMatch.2), clickedIdx >= 1
        {
            let stem = String(numMatch.1)
            var foundNum: [Int: String] = [:]
            for s in siblings {
                if let m = s.wholeMatch(of: /^(.+)\.(\d{3})$/),
                    String(m.1).caseInsensitiveCompare(stem) == .orderedSame,
                    let n = Int(m.2), n >= 1
                {
                    foundNum[n] = s
                }
            }
            let maxIdx = max(clickedIdx, foundNum.keys.max() ?? 1, 2)
            var ordered: [URL] = []
            for idx in 1...maxIdx {
                let expected = String(format: "%@.%03d", stem, idx)
                guard let name = foundNum[idx] else {
                    throw ArchiveError.missingSplitPiece(expected)
                }
                let pieceURL = folder.appendingPathComponent(name)
                guard fm.fileExists(atPath: pieceURL.path) else {
                    throw ArchiveError.missingSplitPiece(name)
                }
                ordered.append(pieceURL)
            }
            let is7z = stem.lowercased().hasSuffix(".7z")
            let nextName = String(format: "%@.%03d", stem, maxIdx + 1)
            if is7z, let expectedBytes = sevenZipExpectedSize(in: ordered[0]) {
                let actualBytes = ordered.reduce(Int64(0)) { sum, piece in
                    sum + Int64((try? piece.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }
                if actualBytes < expectedBytes {
                    throw ArchiveError.missingSplitPiece(nextName)
                }
            }
            return SplitArchive(pieces: ordered, needsConcatenation: !is7z, nextPieceName: nextName)
        }

        return nil
    }

    private static func splitZipDiskCount(in zipURL: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: zipURL) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize >= 22 else { return nil }
        let maxTail = min(fileSize, 65_535 + 22)
        try? handle.seek(toOffset: fileSize - maxTail)
        guard let tail = try? handle.readToEnd(), tail.count >= 22 else { return nil }
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            let sig =
                UInt32(tail[i])
                | (UInt32(tail[i + 1]) << 8)
                | (UInt32(tail[i + 2]) << 16)
                | (UInt32(tail[i + 3]) << 24)
            if sig == 0x0605_4b50 {
                let diskNumber = Int(UInt16(tail[i + 4]) | (UInt16(tail[i + 5]) << 8))
                return diskNumber
            }
        }
        return nil
    }

    private static func isMultiVolumeRAR(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 32), header.count >= 14 else { return false }
        let rar4Sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
        let rar5Sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
        if header.starts(with: rar4Sig) {
            guard header[9] == 0x73 else { return false }
            let flags = UInt16(header[10]) | (UInt16(header[11]) << 8)
            return (flags & 0x0001) != 0
        }
        if header.starts(with: rar5Sig) {
            var pos = 12  // Skip 8-byte signature + 4-byte CRC32
            func readVint() -> UInt64? {
                var result: UInt64 = 0
                var shift: UInt64 = 0
                while pos < header.count {
                    let byte = header[pos]
                    pos += 1
                    result |= UInt64(byte & 0x7F) << shift
                    if (byte & 0x80) == 0 { return result }
                    shift += 7
                    if shift > 63 { return nil }
                }
                return nil
            }
            guard let _ = readVint(),
                let headerType = readVint(), headerType == 1,
                let headerFlags = readVint()
            else { return false }
            if (headerFlags & 0x0001) != 0 {
                guard let _ = readVint() else { return false }
            }
            guard let archiveFlags = readVint() else { return false }
            return (archiveFlags & 0x0001) != 0
        }
        return false
    }

    private static func sevenZipExpectedSize(in firstPiece: URL) -> Int64? {
        guard let handle = try? FileHandle(forReadingFrom: firstPiece) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 32), header.count == 32 else { return nil }
        let sig: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
        guard header.starts(with: sig) else { return nil }
        func u64(_ offset: Int) -> UInt64 {
            var val: UInt64 = 0
            for i in 0..<8 {
                val |= UInt64(header[offset + i]) << (i * 8)
            }
            return val
        }
        let nextHeaderOffset = u64(12)
        let nextHeaderSize = u64(20)
        let (sum1, ov1) = nextHeaderOffset.addingReportingOverflow(nextHeaderSize)
        let (total, ov2) = sum1.addingReportingOverflow(32)
        guard !ov1, !ov2, let signed = Int64(exactly: total) else { return nil }
        return signed
    }

    private static func openReader(
        _ a: OpaquePointer, for archive: URL
    ) throws -> (totalBytes: Int64, split: SplitArchive?, cleanup: () -> Void) {
        guard let split = try resolveSplitPieces(for: archive) else {
            guard archive_read_open_filename(a, archive.path, chunk) == ARCHIVE_OK else {
                throw ArchiveError.unreadable(message(a))
            }
            let size = Int64((try? archive.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            return (size, nil, {})
        }

        let totalBytes = split.pieces.reduce(Int64(0)) { sum, piece in
            sum + Int64((try? piece.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        if split.needsConcatenation {
            let fm = FileManager.default
            let tempURL = fm.temporaryDirectory.appendingPathComponent(".Zipboy-split-\(UUID().uuidString)")
            guard fm.createFile(atPath: tempURL.path, contents: nil) else {
                throw ArchiveError.unreadable("Could not create temporary staging file for split archive.")
            }
            do {
                let out = try FileHandle(forWritingTo: tempURL)
                defer { try? out.close() }
                for piece in split.pieces {
                    let input = try FileHandle(forReadingFrom: piece)
                    defer { try? input.close() }
                    while let data = try input.read(upToCount: chunk), !data.isEmpty {
                        try out.write(contentsOf: data)
                    }
                }
            } catch {
                try? fm.removeItem(at: tempURL)
                throw ArchiveError.unreadable(error.localizedDescription)
            }
            guard archive_read_open_filename(a, tempURL.path, chunk) == ARCHIVE_OK else {
                try? fm.removeItem(at: tempURL)
                throw ArchiveError.unreadable(message(a))
            }
            return (totalBytes, split, { try? fm.removeItem(at: tempURL) })
        }

        var cStrings: [UnsafeMutablePointer<CChar>?] = split.pieces.map { strdup($0.path) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        var constPointers: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
        guard archive_read_open_filenames(a, &constPointers, chunk) == ARCHIVE_OK else {
            throw ArchiveError.unreadable(message(a))
        }
        return (totalBytes, split, {})
    }

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
        let utf8Flagged = utf8FlaggedNames(in: archive, encoding: encoding)
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        // Container formats only. "All" would include mtree, a text format for describing file trees,
        // which claims plain text files as archives of empty entries.
        for support in formats { _ = support(a) }
        if let password { archive_read_add_passphrase(a, password) }
        let (totalBytes, splitInfo, cleanup) = try openReader(a, for: archive)
        defer { cleanup() }

        let total = Double(totalBytes)
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
                let reason = message(a)
                if reason.localizedCaseInsensitiveContains("malformed 64-bit uncompressed size")
                    || reason.localizedCaseInsensitiveContains("malformed 64-bit compressed size")
                {
                    throw ArchiveError.suspiciousArchive(
                        "An entry declares a 64-bit size that overflows (\(reason)) and cannot be trusted."
                    )
                }
                if let nextPiece = splitInfo?.nextPieceName,
                    reason.localizedCaseInsensitiveContains("truncated")
                        || reason.localizedCaseInsensitiveContains("premature end")
                        || reason.localizedCaseInsensitiveContains("failed to open")
                {
                    throw ArchiveError.missingSplitPiece(nextPiece)
                }
                throw ArchiveError.unreadable(reason)
            }
            if status == ARCHIVE_WARN {
                let warning = message(a)
                if warning.localizedCaseInsensitiveContains("inconsistent uncompressed size")
                    || warning.localizedCaseInsensitiveContains("inconsistent compressed size")
                {
                    throw ArchiveError.suspiciousArchive(
                        "The archive’s local header and central directory disagree on an entry’s size (\(warning))."
                    )
                }
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

            let raw = name(of: entry, in: a, encoding: encoding, utf8Flagged: utf8Flagged)
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
                    let targetSize =
                        (try? fm.attributesOfItem(atPath: targetURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                    try expansion.admit(declared: targetSize, path: path)
                    try expansion.add(targetSize, consumed: archive_filter_bytes(a, -1))
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
                        var didDeflate64 = false
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
                                        named: raw, occurrence: occ, from: archive, encoding: encoding, to: out,
                                        budget: &budget, capacity: capacity, report: report,
                                        admit: { bytes, consumed in
                                            try expansion.add(bytes, consumed: before + Int64(consumed))
                                        })
                                    didDeflate64 = true
                                    break
                                }
                                if encrypted { throw ArchiveError.wrongPassword }
                                let reason = message(a)
                                if reason.localizedCaseInsensitiveContains("uncompressed data is wrong size") {
                                    throw ArchiveError.suspiciousArchive(
                                        "The entry “\(path)” disagreed with its declared size and was stopped."
                                    )
                                }
                                if let nextPiece = splitInfo?.nextPieceName,
                                    reason.localizedCaseInsensitiveContains("truncated")
                                        || reason.localizedCaseInsensitiveContains("premature end")
                                {
                                    throw ArchiveError.missingSplitPiece(nextPiece)
                                }
                                throw ArchiveError.unreadable(reason)
                            }
                            let chunkBytes = Int64(n)
                            if sizeSet, size >= 0, !isXar(a), written + chunkBytes > size {
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
                        if !didDeflate64, sizeSet, size >= 0, !isXar(a), written != size {
                            if let nextPiece = splitInfo?.nextPieceName {
                                throw ArchiveError.missingSplitPiece(nextPiece)
                            }
                            throw ArchiveError.suspiciousArchive(
                                "The entry “\(path)” ended at \(written) bytes instead of its declared \(size) bytes."
                            )
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
        if let mark = quarantine(of: archive) {
            stampQuarantine(mark, under: root)
        }
        // Last, because writing a folder's contents moves its date.
        for (url, date) in folders.reversed() {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return summary
    }

    public static let quarantineAttribute = "com.apple.quarantine"

    /// Reads the `com.apple.quarantine` extended attribute on `url` without following symlinks.
    public static func quarantine(of url: URL) -> Data? {
        let length = getxattr(url.path, quarantineAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard length >= 0 else { return nil }
        if length == 0 { return Data() }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes {
            getxattr(url.path, quarantineAttribute, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        guard read >= 0 else { return nil }
        return Data(data.prefix(read))
    }

    /// Copies `com.apple.quarantine` from `source` onto `destination` when `source` carries it.
    public static func copyQuarantine(from source: URL, to destination: URL) {
        guard let mark = quarantine(of: source) else { return }
        setQuarantine(mark, on: destination)
    }

    public static func setQuarantine(_ mark: Data, on url: URL) {
        _ = mark.withUnsafeBytes {
            setxattr(url.path, quarantineAttribute, $0.baseAddress, mark.count, 0, XATTR_NOFOLLOW)
        }
    }

    private static func stampQuarantine(_ mark: Data, under root: URL) {
        func walk(_ dir: URL) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names {
                let item = dir.appendingPathComponent(name)
                setQuarantine(mark, on: item)
                if isDirectory(item) { walk(item) }
            }
        }
        walk(root)
    }

    /// Reads the target path of a symlink `entry` from `sourceZip` (or `sourceHandle`) without writing
    /// anything to disk.
    public static func readSymlinkTarget(
        _ entry: ZipCatalog.Entry,
        from sourceZip: URL,
        sourceHandle: FileHandle? = nil
    ) -> String? {
        guard entry.isSymlink, !entry.isEncrypted else { return nil }
        guard let data = try? readEntryData(entry, from: sourceZip, sourceHandle: sourceHandle, maxBytes: 4096) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Extracts a single `ZipCatalog.Entry` from `sourceZip` (or `sourceHandle`) to `destination`
    /// atomically via a staging file. When `quarantineRoot` or `quarantineMark` is supplied, the
    /// archive's quarantine attribute is applied to `destination` and any parent directories created
    /// under `quarantineRoot`.
    public static func extractEntry(
        _ entry: ZipCatalog.Entry,
        from sourceZip: URL,
        sourceHandle: FileHandle? = nil,
        to destination: URL,
        quarantineRoot: URL? = nil,
        quarantineMark: Data? = nil,
        encoding: TextEncoding = .auto,
        progress: ((Int64) -> Bool)? = nil
    ) throws {
        let fm = FileManager.default
        let mark = quarantineMark ?? quarantine(of: sourceZip)

        func ensureParents(of target: URL) throws {
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if let mark, let root = quarantineRoot {
                let rootPath = root.standardizedFileURL.path
                var dir = parent.standardizedFileURL
                while dir.path.count > rootPath.count && dir.path.hasPrefix(rootPath) {
                    setQuarantine(mark, on: dir)
                    dir.deleteLastPathComponent()
                }
            }
        }

        if entry.isDirectory {
            try ensureParents(of: destination)
            if !isDirectory(destination) {
                try? fm.removeItem(at: destination)
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            }
            let perm = (entry.posixPermissions != 0 ? entry.posixPermissions : 0o755) | 0o700
            var attrs: [FileAttributeKey: Any] = [.posixPermissions: perm]
            if let modified = entry.modified { attrs[.modificationDate] = modified }
            try? fm.setAttributes(attrs, ofItemAtPath: destination.path)
            if let mark { setQuarantine(mark, on: destination) }
            return
        }

        if entry.isSymlink {
            let data = try readEntryData(entry, from: sourceZip, sourceHandle: sourceHandle, maxBytes: 65_536)
            let target = String(data: data, encoding: .utf8) ?? ""
            guard EntryPath.linkStaysInside(path: entry.path, target: target) else { return }
            try ensureParents(of: destination)
            try? fm.removeItem(at: destination)
            try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
            if let mark { setQuarantine(mark, on: destination) }
            return
        }

        try ensureParents(of: destination)
        let stagingDir = quarantineRoot?.deletingLastPathComponent() ?? destination.deletingLastPathComponent()
        let staging = stagingDir.appendingPathComponent(".Zipboy-mat-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }

        guard fm.createFile(atPath: staging.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: staging.path])
        }

        if !entry.isEncrypted && (entry.method == 0 || entry.method == 8) {
            let ownedHandle: FileHandle? = sourceHandle == nil ? try FileHandle(forReadingFrom: sourceZip) : nil
            defer { try? ownedHandle?.close() }
            guard let inHandle = sourceHandle ?? ownedHandle else {
                throw ArchiveError.unreadable("Missing source archive.")
            }
            let out = try FileHandle(forWritingTo: staging)
            defer { try? out.close() }
            try streamZipPayload(
                entry,
                fromFD: inHandle.fileDescriptor,
                toFD: out.fileDescriptor,
                progress: progress
            )
        } else if !entry.isEncrypted && entry.method == 9 {
            let out = try FileHandle(forWritingTo: staging)
            defer { try? out.close() }
            var budget: Int64? = nil
            try Deflate64.extract(
                named: entry.rawPath,
                occurrence: 0,
                from: sourceZip,
                encoding: encoding,
                to: out,
                budget: &budget,
                capacity: { nil },
                report: {
                    if let progress, !progress(0) { throw ArchiveError.cancelled }
                },
                admit: { _, _ in }
            )
        } else {
            try extractSingleViaLibarchive(
                entryPath: entry.path,
                from: sourceZip,
                encoding: encoding,
                to: staging,
                progress: progress
            )
        }

        let perm = (entry.posixPermissions != 0 ? entry.posixPermissions : 0o644) | 0o600
        var attrs: [FileAttributeKey: Any] = [.posixPermissions: perm]
        if let modified = entry.modified { attrs[.modificationDate] = modified }
        try fm.setAttributes(attrs, ofItemAtPath: staging.path)
        if let mark { setQuarantine(mark, on: staging) }
        guard rename(staging.path, destination.path) == 0 else {
            throw unwritable(errno)
        }
    }

    private static func readEntryData(
        _ entry: ZipCatalog.Entry,
        from sourceZip: URL,
        sourceHandle: FileHandle?,
        maxBytes: Int
    ) throws -> Data {
        let ownedHandle: FileHandle? = sourceHandle == nil ? try FileHandle(forReadingFrom: sourceZip) : nil
        defer { try? ownedHandle?.close() }
        guard let inHandle = sourceHandle ?? ownedHandle else {
            throw ArchiveError.unreadable("Missing source archive.")
        }
        let fd = inHandle.fileDescriptor
        let dataOffset = try payloadOffset(of: entry, inFD: fd)
        let compLen = Int(min(entry.compressedSize, UInt64(maxBytes * 2 + 64)))
        var compBuf = [UInt8](repeating: 0, count: compLen)
        guard let pos = off_t(exactly: dataOffset) else {
            throw ArchiveError.unreadable("ZIP entry offset out of bounds.")
        }
        let readCount = try compBuf.withUnsafeMutableBufferPointer { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return try preadBytes(fd: fd, into: base, count: compLen, offset: pos)
        }
        if entry.method == 0 {
            return Data(compBuf.prefix(min(readCount, maxBytes)))
        }
        guard entry.method == 8 else {
            throw ArchiveError.unreadable("Unsupported compression method for symlink.")
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ArchiveError.unreadable("Failed to initialize Deflate decoder.")
        }
        defer { inflateEnd(&stream) }
        let outCap = min(max(Int(entry.uncompressedSize), 256), maxBytes)
        var outBuf = [UInt8](repeating: 0, count: outCap)
        let produced: Int = try compBuf.withUnsafeMutableBufferPointer { rawIn in
            try outBuf.withUnsafeMutableBufferPointer { rawOut in
                stream.next_in = rawIn.baseAddress
                stream.avail_in = uInt(readCount)
                stream.next_out = rawOut.baseAddress
                stream.avail_out = uInt(outCap)
                let status = zlib.inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END || status == Z_OK || status == Z_BUF_ERROR else {
                    throw ArchiveError.unreadable("Corrupt Deflate stream.")
                }
                return outCap - Int(stream.avail_out)
            }
        }
        return Data(outBuf.prefix(produced))
    }

    private static func payloadOffset(of entry: ZipCatalog.Entry, inFD fd: Int32) throws -> UInt64 {
        var local = [UInt8](repeating: 0, count: 30)
        guard let headerPos = off_t(exactly: entry.localHeaderOffset) else {
            throw ArchiveError.unreadable("ZIP entry offset out of bounds.")
        }
        let readHeader = try local.withUnsafeMutableBufferPointer { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return try preadBytes(fd: fd, into: base, count: 30, offset: headerPos)
        }
        let sig =
            UInt32(local[0]) | (UInt32(local[1]) << 8) | (UInt32(local[2]) << 16) | (UInt32(local[3]) << 24)
        guard readHeader == 30, sig == 0x0403_4b50 else {
            throw ArchiveError.unreadable("Corrupt Local File Header for “\(entry.path)”.")
        }
        let localNameLen = UInt64(local[26]) | (UInt64(local[27]) << 8)
        let localExtraLen = UInt64(local[28]) | (UInt64(local[29]) << 8)
        return entry.localHeaderOffset + 30 + localNameLen + localExtraLen
    }

    private static func streamZipPayload(
        _ entry: ZipCatalog.Entry,
        fromFD inFD: Int32,
        toFD outFD: Int32,
        progress: ((Int64) -> Bool)?
    ) throws {
        let dataOffset = try payloadOffset(of: entry, inFD: inFD)
        var crc: uLong = zlib.crc32(0, nil, 0)
        var totalOut: UInt64 = 0
        var remainingIn = entry.compressedSize
        var currentOffset = dataOffset

        if let progress, !progress(0) { throw ArchiveError.cancelled }

        if entry.method == 0 {
            var buf = [UInt8](repeating: 0, count: Int(min(UInt64(chunk), max(remainingIn, 1))))
            while remainingIn > 0 {
                let step = Int(min(UInt64(buf.count), remainingIn))
                guard let pos = off_t(exactly: currentOffset) else {
                    throw ArchiveError.unreadable("ZIP entry offset out of bounds.")
                }
                let n = try buf.withUnsafeMutableBufferPointer { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return try preadBytes(fd: inFD, into: base, count: step, offset: pos)
                }
                guard n > 0 else {
                    throw ArchiveError.unreadable("Unexpected end of file while reading “\(entry.path)”.")
                }
                buf.withUnsafeBufferPointer { raw in
                    if let base = raw.baseAddress {
                        crc = zlib.crc32(crc, base, uInt(n))
                    }
                }
                try buf.withUnsafeBufferPointer { raw in
                    if let base = raw.baseAddress {
                        try writeAllFD(fd: outFD, from: base, count: n)
                    }
                }
                currentOffset += UInt64(n)
                remainingIn -= UInt64(n)
                totalOut += UInt64(n)
                if let progress, !progress(Int64(clamping: totalOut)) {
                    throw ArchiveError.cancelled
                }
            }
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw ArchiveError.unreadable("Failed to initialize Deflate decoder.")
            }
            defer { inflateEnd(&stream) }

            var inBuf = [UInt8](repeating: 0, count: Int(min(UInt64(chunk), max(remainingIn, 1))))
            var outBuf = [UInt8](repeating: 0, count: chunk)
            var finishedStream = remainingIn == 0 && entry.uncompressedSize == 0

            while remainingIn > 0 && !finishedStream {
                let step = Int(min(UInt64(inBuf.count), remainingIn))
                guard let pos = off_t(exactly: currentOffset) else {
                    throw ArchiveError.unreadable("ZIP entry offset out of bounds.")
                }
                let n = try inBuf.withUnsafeMutableBufferPointer { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return try preadBytes(fd: inFD, into: base, count: step, offset: pos)
                }
                guard n > 0 else {
                    throw ArchiveError.unreadable("Unexpected end of file while reading “\(entry.path)”.")
                }
                currentOffset += UInt64(n)
                remainingIn -= UInt64(n)

                try inBuf.withUnsafeMutableBufferPointer { rawIn in
                    stream.next_in = rawIn.baseAddress
                    stream.avail_in = uInt(n)
                    while stream.avail_in > 0 && !finishedStream {
                        let (produced, status) = try outBuf.withUnsafeMutableBufferPointer { rawOut -> (Int, Int32) in
                            stream.next_out = rawOut.baseAddress
                            stream.avail_out = uInt(rawOut.count)
                            let st = zlib.inflate(&stream, Z_NO_FLUSH)
                            guard st == Z_OK || st == Z_STREAM_END else {
                                throw ArchiveError.unreadable("Corrupt Deflate data in “\(entry.path)”.")
                            }
                            return (rawOut.count - Int(stream.avail_out), st)
                        }
                        if produced > 0 {
                            outBuf.withUnsafeBufferPointer { rawOut in
                                if let base = rawOut.baseAddress {
                                    crc = zlib.crc32(crc, base, uInt(produced))
                                }
                            }
                            try outBuf.withUnsafeBufferPointer { rawOut in
                                if let base = rawOut.baseAddress {
                                    try writeAllFD(fd: outFD, from: base, count: produced)
                                }
                            }
                            totalOut += UInt64(produced)
                            if let progress, !progress(Int64(clamping: totalOut)) {
                                throw ArchiveError.cancelled
                            }
                        }
                        if status == Z_STREAM_END {
                            finishedStream = true
                        }
                    }
                }
            }
            guard finishedStream else {
                throw ArchiveError.unreadable("Truncated Deflate stream in “\(entry.path)”.")
            }
        }

        guard totalOut == entry.uncompressedSize else {
            throw ArchiveError.suspiciousArchive(
                "The entry “\(entry.path)” uncompressed to \(totalOut) bytes instead of its declared \(entry.uncompressedSize) bytes."
            )
        }
        guard UInt32(truncatingIfNeeded: crc) == entry.crc32 else {
            throw ArchiveError.unreadable("Bad CRC-32 checksum in “\(entry.path)”.")
        }
    }

    private static func extractSingleViaLibarchive(
        entryPath: String,
        from archive: URL,
        encoding: TextEncoding,
        to staging: URL,
        progress: ((Int64) -> Bool)?
    ) throws {
        useUTF8Names()
        let utf8Flagged = utf8FlaggedNames(in: archive, encoding: encoding)
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        for support in formats { _ = support(a) }
        guard archive_read_open_filename(a, archive.path, chunk) == ARCHIVE_OK else {
            throw ArchiveError.unreadable(message(a))
        }
        var buffer = [UInt8](repeating: 0, count: chunk)
        var entry: OpaquePointer?
        while archive_read_next_header(a, &entry) >= ARCHIVE_WARN, let current = entry {
            let raw = name(of: current, in: a, encoding: encoding, utf8Flagged: utf8Flagged)
            guard EntryPath.sanitized(raw) == entryPath else {
                archive_read_data_skip(a)
                continue
            }
            let out = try FileHandle(forWritingTo: staging)
            defer { try? out.close() }
            var written: Int64 = 0
            while true {
                let n = archive_read_data(a, &buffer, buffer.count)
                if n == 0 { return }
                if n < 0 { throw ArchiveError.unreadable(message(a)) }
                try out.write(contentsOf: buffer[0..<n])
                written += Int64(n)
                if let progress, !progress(written) { throw ArchiveError.cancelled }
            }
        }
        throw ArchiveError.unreadable("Entry “\(entryPath)” not found in archive.")
    }

    private static func preadBytes(
        fd: Int32, into buffer: UnsafeMutablePointer<UInt8>, count: Int, offset: off_t
    ) throws -> Int {
        var total = 0
        while total < count {
            let n = Darwin.pread(fd, buffer.advanced(by: total), count - total, offset + off_t(total))
            if n > 0 {
                total += n
            } else if n == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw ArchiveError.unreadable(String(cString: strerror(errno)))
            }
        }
        return total
    }

    private static func writeAllFD(fd: Int32, from buffer: UnsafePointer<UInt8>, count: Int) throws {
        var offset = 0
        while offset < count {
            let n = Darwin.write(fd, buffer.advanced(by: offset), count - offset)
            if n > 0 {
                offset += n
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                throw unwritable(errno)
            }
        }
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
            guard overflow || (after > Self.floor && Self.exceedsRatio(after, base: archiveBytes)) else { return }
            throw ArchiveError.suspiciousArchive(
                "The entry “\(path)” would expand to more than \(Self.ratio)× the archive’s size and was stopped to protect against a decompression bomb."
            )
        }

        /// Counts `bytes` about to be written, `consumed` being the compressed bytes read so far. The
        /// running ratio catches a bomb whose declared sizes hide behind padding later in the file.
        mutating func add(_ bytes: Int64, consumed: Int64) throws {
            let (after, overflow) = expanded.addingReportingOverflow(bytes)
            if overflow || (after > Self.floor && Self.exceedsRatio(after, base: consumed)) {
                throw ArchiveError.suspiciousArchive(
                    "This archive expanded past \(ByteCountFormatter.string(fromByteCount: Self.floor, countStyle: .file)) at more than \(Self.ratio)× its compressed size and was stopped to protect against a decompression bomb."
                )
            }
            expanded = after
        }

        private static func exceedsRatio(_ expanded: Int64, base: Int64) -> Bool {
            let (limit, overflow) = max(base, 1).multipliedReportingOverflow(by: Self.ratio)
            return !overflow && expanded > limit
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

        try commit(staging, to: destination)
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
        let utf8Flagged = utf8FlaggedNames(in: archive, encoding: encoding)
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        for support in formats { _ = support(a) }
        if let password { archive_read_add_passphrase(a, password) }
        let (totalBytes, splitInfo, cleanup) = try openReader(a, for: archive)
        defer { cleanup() }

        let total = Double(totalBytes)
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
                let reason = message(a)
                if reason.localizedCaseInsensitiveContains("malformed 64-bit uncompressed size")
                    || reason.localizedCaseInsensitiveContains("malformed 64-bit compressed size")
                {
                    throw ArchiveError.suspiciousArchive(
                        "An entry declares a 64-bit size that overflows (\(reason)) and cannot be trusted."
                    )
                }
                if let nextPiece = splitInfo?.nextPieceName,
                    reason.localizedCaseInsensitiveContains("truncated")
                        || reason.localizedCaseInsensitiveContains("premature end")
                        || reason.localizedCaseInsensitiveContains("failed to open")
                {
                    throw ArchiveError.missingSplitPiece(nextPiece)
                }
                throw ArchiveError.unreadable(reason)
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

            let raw = name(of: entry, in: a, encoding: encoding, utf8Flagged: utf8Flagged)
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
                                named: raw, occurrence: occ, from: archive, encoding: encoding, to: devNull,
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
    /// `.tar.xz`, `.tar`, or `.7z`) atomically via a staging file. A password encrypts a ZIP; any other
    /// format throws `cantEncrypt`, since libarchive writes those only in plaintext.
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
        if let password, !password.isEmpty { throw ArchiveError.cantEncrypt(format) }
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

        try commit(staging, to: destination)
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

    /// Moves a finished `staging` file over `destination` so that a power cut leaves either the old
    /// archive or the new one: the file reaches the disk before the rename, and the rename before this
    /// returns.
    static func commit(_ staging: URL, to destination: URL) throws {
        try flush(staging, required: true)
        guard rename(staging.path, destination.path) == 0 else { throw unwritable(errno) }
        // Some volumes can't flush a folder, and a drop box can't be opened to try; the archive itself
        // is already on the disk by then.
        try flush(destination.deletingLastPathComponent(), required: false)
    }

    /// Plain `fsync` on macOS stops at the drive's cache; `F_FULLFSYNC` asks the drive to write it out.
    /// Volumes that refuse `F_FULLFSYNC`, such as FAT and network shares, get `fsync`, the best they offer.
    private static func flush(_ url: URL, required: Bool) throws {
        let fd = open(url.path, O_RDONLY)
        let flushed = fd >= 0 && (fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0)
        let code = errno
        if fd >= 0 { close(fd) }
        if flushed { return }
        if required || ![ENOTSUP, EINVAL, EACCES].contains(code) { throw unwritable(code) }
    }

    private static func unwritable(_ code: Int32) -> ArchiveError {
        .unwritable(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO).localizedDescription)
    }

    static func freeSpace(on url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// What `archive` holds, read without unpacking anything: a ZIP's central directory, or the headers
    /// of any other format, skipping over each entry's data. Stops after `limit` entries. An archive whose
    /// names are themselves encrypted, as a 7z or RAR can be, comes back with `namesHidden`.
    public static func list(_ archive: URL, limit: Int = 10_000) throws -> ArchiveListing {
        if let catalog = try? ZipCatalog.read(from: archive) {
            let entries = catalog.entries.prefix(limit).map {
                ArchiveListing.Entry(
                    path: $0.path, size: Int64(clamping: $0.uncompressedSize), isDirectory: $0.isDirectory,
                    modified: $0.modified)
            }
            return ArchiveListing(
                format: "ZIP", entries: Array(entries), isTruncated: catalog.entries.count > limit,
                isEncrypted: catalog.isEncrypted, namesHidden: false)
        }
        useUTF8Names()
        guard let a = archive_read_new() else { throw ArchiveError.unreadable("Out of memory.") }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        for support in formats { _ = support(a) }
        let (_, _, cleanup) = try openReader(a, for: archive)
        defer { cleanup() }
        var entries: [ArchiveListing.Entry] = []
        var encrypted = false
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else {
                if entries.isEmpty, isPasswordProblem(a) {
                    return ArchiveListing(
                        format: formatName(a), entries: [], isTruncated: false, isEncrypted: true, namesHidden: true)
                }
                // A damaged tail still leaves the entries before it worth showing.
                if entries.isEmpty { throw ArchiveError.unreadable(message(a)) }
                break
            }
            if entries.count == limit {
                return ArchiveListing(
                    format: formatName(a), entries: entries, isTruncated: true, isEncrypted: encrypted,
                    namesHidden: false)
            }
            let path = name(of: entry, in: a)
            let isDirectory = archive_entry_filetype(entry) & mode_t(AE_IFMT) == mode_t(AE_IFDIR) || path.hasSuffix("/")
            encrypted = encrypted || archive_entry_is_encrypted(entry) != 0
            entries.append(
                ArchiveListing.Entry(
                    path: path.hasSuffix("/") ? String(path.dropLast()) : path,
                    size: archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : 0,
                    isDirectory: isDirectory,
                    modified: archive_entry_mtime_is_set(entry) != 0
                        ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil))
            // An encrypted 7z can't even skip its data; what was listed so far still stands.
            if archive_read_data_skip(a) < ARCHIVE_WARN { break }
        }
        return ArchiveListing(
            format: formatName(a), entries: entries, isTruncated: false, isEncrypted: encrypted, namesHidden: false)
    }

    /// The first picture in `archive` that is small enough to read whole and isn't encrypted, for a
    /// thumbnail. Looks at no more than `scanLimit` entries, so a huge archive with no pictures gives
    /// up quickly, and never asks for or tries a password.
    public static func firstImage(
        in archive: URL, maxBytes: Int64 = 20 << 20, scanLimit: Int = 2_000
    ) -> (path: String, data: Data)? {
        useUTF8Names()
        guard let a = archive_read_new() else { return nil }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        for support in formats { _ = support(a) }
        guard let (_, _, cleanup) = try? openReader(a, for: archive) else { return nil }
        defer { cleanup() }
        var entry: OpaquePointer?
        for _ in 0..<scanLimit {
            guard archive_read_next_header(a, &entry) >= ARCHIVE_WARN, let entry else { return nil }
            let path = name(of: entry, in: a)
            let size = archive_entry_size(entry)
            guard archive_entry_filetype(entry) & mode_t(AE_IFMT) == mode_t(AE_IFREG),
                pictureExtensions.contains((path as NSString).pathExtension.lowercased()),
                archive_entry_is_encrypted(entry) == 0, size > 0, size <= maxBytes
            else {
                if archive_read_data_skip(a) < ARCHIVE_WARN { return nil }
                continue
            }
            // libarchive hands data back in pieces, however big the buffer.
            var data = Data(count: Int(size))
            var filled = 0
            while filled < Int(size) {
                let read = data.withUnsafeMutableBytes {
                    archive_read_data(a, $0.baseAddress! + filled, Int(size) - filled)
                }
                guard read > 0 else { return nil }
                filled += read
            }
            return (path, data)
        }
        return nil
    }

    static let pictureExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp",
    ]

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
    /// that aren't valid UTF-8 are read as CP437 rather than shown as "". A chosen `encoding` applies
    /// only to unflagged names, as in `ZipCatalog`, or the catalog's paths would stop matching these.
    private static func name(
        of entry: OpaquePointer, in a: OpaquePointer, encoding: TextEncoding = .auto,
        utf8Flagged: Set<String> = []
    ) -> String {
        if let stored = archive_entry_pathname(entry) {
            let bytes = Data(bytes: stored, count: strlen(stored))
            if encoding != .auto {
                // libarchive hands a flagged name back decomposed, so it is matched as text, not bytes.
                if isZip(a), let utf8 = String(data: bytes, encoding: .utf8), utf8Flagged.contains(utf8) {
                    return utf8
                }
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

    /// The names a ZIP flags as UTF-8, which libarchive reads but doesn't report. Only a chosen encoding
    /// needs them: Automatic reads valid UTF-8 as UTF-8 anyway. Anything the catalog can't read, such as
    /// a RAR, has no flags, so its names all take the chosen encoding.
    private static func utf8FlaggedNames(in archive: URL, encoding: TextEncoding) -> Set<String> {
        guard encoding != .auto, let catalog = try? ZipCatalog.read(from: archive) else { return [] }
        return Set(catalog.entries.filter(\.usesUTF8Flag).compactMap { String(data: $0.rawName, encoding: .utf8) })
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
    private static let utf8Locale: Void = {
        _ = setlocale(LC_CTYPE, "UTF-8")
    }()
}
