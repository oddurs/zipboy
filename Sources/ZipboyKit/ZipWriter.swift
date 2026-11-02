import Darwin
import Foundation
import zlib

/// Writes a `.zip` archive by copying unchanged entries verbatim from a source ZIP and compressing
/// only new or modified files from the workspace. Supports Zip64 (> 4 GB and > 65,535 entries).
public enum ZipWriter {
    public enum Item: Sendable {
        /// Copies the compressed payload (and local header when `newPath` is nil) directly from `source`.
        case verbatim(ZipCatalog.Entry, newPath: String? = nil)
        /// Reads and compresses (or stores) a workspace item at `url` into archive path `path`.
        case workspace(url: URL, path: String)
    }

    private struct CentralRecord {
        let versionMadeBy: UInt16
        let versionNeeded: UInt16
        let flags: UInt16
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let internalAttributes: UInt16
        let externalAttributes: UInt32
        let nameBytes: Data
        let comment: Data
    }

    private static let chunkSize = 256 * 1024

    /// Writes `items` to `destination` atomically, reading `.verbatim` items from `sourceZip`.
    public static func write(
        items: [Item],
        sourceZip: URL?,
        to destination: URL,
        compressionLevel: Settings.CompressionLevel = .balanced,
        comment: Data = Data(),
        progress: ((Double) -> Bool)? = nil
    ) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".Zipboy-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: staging) }

        guard fm.createFile(atPath: staging.path, contents: nil) else {
            throw ArchiveError.unwritable("Could not create staging archive at \(staging.path).")
        }

        let out = try FileHandle(forWritingTo: staging)
        defer { try? out.close() }

        let sourceHandle: FileHandle? =
            if let sourceZip, items.contains(where: { if case .verbatim = $0 { true } else { false } }) {
                try FileHandle(forReadingFrom: sourceZip)
            } else {
                nil
            }
        defer { try? sourceHandle?.close() }

        let totalWork: Int64 = items.reduce(0) { sum, item in
            switch item {
            case .verbatim(let entry, _):
                return sum + Int64(entry.compressedSize)
            case .workspace(let url, _):
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                return sum + max(0, size)
            }
        }
        var completedWork: Int64 = 0
        func report(_ delta: Int64) throws {
            completedWork += delta
            guard let progress else { return }
            let fraction = totalWork <= 0 ? 1.0 : min(1.0, Double(completedWork) / Double(totalWork))
            guard progress(fraction) else { throw ArchiveError.cancelled }
        }

        var centralRecords: [CentralRecord] = []
        centralRecords.reserveCapacity(items.count)

        try report(0)

        for item in items {
            switch item {
            case .verbatim(let entry, let newPath):
                guard let sourceHandle else {
                    throw ArchiveError.unwritable("Missing source archive for verbatim entry copy.")
                }
                let record = try writeVerbatim(
                    entry: entry,
                    newPath: newPath,
                    from: sourceHandle,
                    to: out,
                    report: report
                )
                centralRecords.append(record)

            case .workspace(let url, let path):
                let record = try writeWorkspaceItem(
                    url: url,
                    path: path,
                    compressionLevel: compressionLevel,
                    to: out,
                    report: report
                )
                centralRecords.append(record)
            }
        }

        let cdOffset = try out.offset()
        var cdBuffer = Data()
        cdBuffer.reserveCapacity(centralRecords.count * 64)

        for rec in centralRecords {
            appendCentralHeader(rec, into: &cdBuffer)
            if cdBuffer.count >= chunkSize {
                try out.write(contentsOf: cdBuffer)
                cdBuffer.removeAll(keepingCapacity: true)
            }
        }
        if !cdBuffer.isEmpty {
            try out.write(contentsOf: cdBuffer)
            cdBuffer.removeAll()
        }

        let cdEnd = try out.offset()
        let cdSize = cdEnd - cdOffset

        var trailer = Data()
        let needsZip64 =
            centralRecords.count >= 0xFFFF
            || cdSize >= 0xFFFF_FFFF
            || cdOffset >= 0xFFFF_FFFF
        if needsZip64 {
            let z64RecordOffset = cdEnd
            // Zip64 End of Central Directory Record (56 bytes)
            appendU32(0x0606_4b50, to: &trailer)
            appendU64(44, to: &trailer)  // size of remaining record
            appendU16(0x031E, to: &trailer)  // version made by (Unix, 3.0)
            appendU16(45, to: &trailer)  // version needed (4.5 for Zip64)
            appendU32(0, to: &trailer)  // disk number
            appendU32(0, to: &trailer)  // disk with central directory
            appendU64(UInt64(centralRecords.count), to: &trailer)
            appendU64(UInt64(centralRecords.count), to: &trailer)
            appendU64(cdSize, to: &trailer)
            appendU64(cdOffset, to: &trailer)

            // Zip64 End of Central Directory Locator (20 bytes)
            appendU32(0x0706_4b50, to: &trailer)
            appendU32(0, to: &trailer)  // disk with Zip64 EOCD
            appendU64(z64RecordOffset, to: &trailer)
            appendU32(1, to: &trailer)  // total number of disks
        }

        // Standard End of Central Directory Record (22 bytes + comment)
        appendU32(0x0605_4b50, to: &trailer)
        appendU16(0, to: &trailer)
        appendU16(0, to: &trailer)
        let count16 = UInt16(min(UInt64(centralRecords.count), 0xFFFF))
        appendU16(count16, to: &trailer)
        appendU16(count16, to: &trailer)
        appendU32(UInt32(min(cdSize, 0xFFFF_FFFF)), to: &trailer)
        appendU32(UInt32(min(cdOffset, 0xFFFF_FFFF)), to: &trailer)
        let clippedComment = comment.prefix(65_535)
        appendU16(UInt16(clippedComment.count), to: &trailer)
        trailer.append(clippedComment)
        try out.write(contentsOf: trailer)
        try out.close()

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

    private static func writeVerbatim(
        entry: ZipCatalog.Entry,
        newPath: String?,
        from sourceHandle: FileHandle,
        to out: FileHandle,
        report: (Int64) throws -> Void
    ) throws -> CentralRecord {
        let localOffset = try out.offset()
        let (payloadOffset, payloadLen) = try ZipCatalog.payloadRange(in: sourceHandle, for: entry)

        let effectiveNameBytes: Data
        let effectiveFlags: UInt16
        if let newPath {
            let normalized =
                entry.isDirectory && !newPath.hasSuffix("/")
                ? newPath.precomposedStringWithCanonicalMapping + "/"
                : newPath.precomposedStringWithCanonicalMapping
            effectiveNameBytes = Data(normalized.utf8)
            effectiveFlags = (entry.flags | (1 << 11)) & ~UInt16(0x0008)
        } else {
            effectiveNameBytes = entry.rawName
            effectiveFlags = entry.flags
        }

        // When the entry was not renamed and has no trailing data descriptor, copy its entire local
        // record (Local File Header + local extra field + compressed payload) verbatim byte-for-byte.
        if newPath == nil && !entry.hasDataDescriptor {
            let totalLocalBytes = (payloadOffset - entry.localHeaderOffset) + payloadLen
            try copyBytes(
                from: sourceHandle,
                offset: entry.localHeaderOffset,
                length: totalLocalBytes,
                to: out,
                reportPayloadOnlyFrom: payloadOffset - entry.localHeaderOffset,
                report: report
            )
            return CentralRecord(
                versionMadeBy: entry.versionMadeBy,
                versionNeeded: entry.versionNeeded,
                flags: entry.flags,
                method: entry.method,
                dosTime: entry.rawDosTime,
                dosDate: entry.rawDosDate,
                crc32: entry.crc32,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                localHeaderOffset: localOffset,
                internalAttributes: entry.internalAttributes,
                externalAttributes: entry.externalAttributes,
                nameBytes: effectiveNameBytes,
                comment: entry.comment
            )
        }

        // Otherwise write a clean Local File Header with the known sizes/CRC and copy the compressed
        // payload bytes verbatim.
        let cleanFlags = effectiveFlags & ~UInt16(0x0008)
        let needsZ64 = entry.compressedSize >= 0xFFFF_FFFF || entry.uncompressedSize >= 0xFFFF_FFFF
        let versionNeeded = max(entry.versionNeeded, needsZ64 ? UInt16(45) : UInt16(20))
        var localExtra = Data()
        if needsZ64 {
            appendU16(0x0001, to: &localExtra)
            appendU16(16, to: &localExtra)
            appendU64(entry.uncompressedSize, to: &localExtra)
            appendU64(entry.compressedSize, to: &localExtra)
        }

        var header = Data()
        header.reserveCapacity(30 + effectiveNameBytes.count + localExtra.count)
        appendU32(0x0403_4b50, to: &header)
        appendU16(versionNeeded, to: &header)
        appendU16(cleanFlags, to: &header)
        appendU16(entry.method, to: &header)
        appendU16(entry.rawDosTime, to: &header)
        appendU16(entry.rawDosDate, to: &header)
        appendU32(entry.crc32, to: &header)
        appendU32(needsZ64 ? 0xFFFF_FFFF : UInt32(entry.compressedSize), to: &header)
        appendU32(needsZ64 ? 0xFFFF_FFFF : UInt32(entry.uncompressedSize), to: &header)
        appendU16(UInt16(effectiveNameBytes.count), to: &header)
        appendU16(UInt16(localExtra.count), to: &header)
        header.append(effectiveNameBytes)
        header.append(localExtra)
        try out.write(contentsOf: header)

        try copyBytes(
            from: sourceHandle,
            offset: payloadOffset,
            length: payloadLen,
            to: out,
            reportPayloadOnlyFrom: 0,
            report: report
        )

        return CentralRecord(
            versionMadeBy: entry.versionMadeBy,
            versionNeeded: versionNeeded,
            flags: cleanFlags,
            method: entry.method,
            dosTime: entry.rawDosTime,
            dosDate: entry.rawDosDate,
            crc32: entry.crc32,
            compressedSize: entry.compressedSize,
            uncompressedSize: entry.uncompressedSize,
            localHeaderOffset: localOffset,
            internalAttributes: entry.internalAttributes,
            externalAttributes: entry.externalAttributes,
            nameBytes: effectiveNameBytes,
            comment: entry.comment
        )
    }

    private static func writeWorkspaceItem(
        url: URL,
        path: String,
        compressionLevel: Settings.CompressionLevel,
        to out: FileHandle,
        report: (Int64) throws -> Void
    ) throws -> CentralRecord {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let fileType = attrs[.type] as? FileAttributeType
        let perms = (attrs[.posixPermissions] as? Int) ?? (fileType == .typeDirectory ? 0o755 : 0o644)
        let modDate = attrs[.modificationDate] as? Date
        let (dosDate, dosTime) = ZipCatalog.encodeDosDate(modDate)

        let isDir = fileType == .typeDirectory
        let isSymlink = fileType == .typeSymbolicLink
        let normalizedPath =
            isDir && !path.hasSuffix("/")
            ? path.precomposedStringWithCanonicalMapping + "/"
            : path.precomposedStringWithCanonicalMapping
        let nameBytes = Data(normalizedPath.utf8)
        let flags: UInt16 = (1 << 11)  // UTF-8 flag

        let unixMode: UInt32 =
            if isDir {
                UInt32(0o040000 | (perms & 0o7777))
            } else if isSymlink {
                UInt32(0o120000 | (perms & 0o7777))
            } else {
                UInt32(0o100000 | (perms & 0o7777))
            }
        let externalAttr = (unixMode << 16) | (isDir ? 0x10 : 0)
        let localOffset = try out.offset()

        if isDir {
            var header = Data()
            appendU32(0x0403_4b50, to: &header)
            appendU16(20, to: &header)
            appendU16(flags, to: &header)
            appendU16(0, to: &header)
            appendU16(dosTime, to: &header)
            appendU16(dosDate, to: &header)
            appendU32(0, to: &header)
            appendU32(0, to: &header)
            appendU32(0, to: &header)
            appendU16(UInt16(nameBytes.count), to: &header)
            appendU16(0, to: &header)
            header.append(nameBytes)
            try out.write(contentsOf: header)

            return CentralRecord(
                versionMadeBy: 0x031E,
                versionNeeded: 20,
                flags: flags,
                method: 0,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: 0,
                compressedSize: 0,
                uncompressedSize: 0,
                localHeaderOffset: localOffset,
                internalAttributes: 0,
                externalAttributes: externalAttr,
                nameBytes: nameBytes,
                comment: Data()
            )
        }

        if isSymlink {
            let target = try fm.destinationOfSymbolicLink(atPath: url.path)
            let targetData = Data(target.precomposedStringWithCanonicalMapping.utf8)
            let crc = computeCRC32(targetData)
            let len = UInt32(targetData.count)
            var header = Data()
            appendU32(0x0403_4b50, to: &header)
            appendU16(20, to: &header)
            appendU16(flags, to: &header)
            appendU16(0, to: &header)
            appendU16(dosTime, to: &header)
            appendU16(dosDate, to: &header)
            appendU32(crc, to: &header)
            appendU32(len, to: &header)
            appendU32(len, to: &header)
            appendU16(UInt16(nameBytes.count), to: &header)
            appendU16(0, to: &header)
            header.append(nameBytes)
            header.append(targetData)
            try out.write(contentsOf: header)

            return CentralRecord(
                versionMadeBy: 0x031E,
                versionNeeded: 20,
                flags: flags,
                method: 0,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: crc,
                compressedSize: UInt64(len),
                uncompressedSize: UInt64(len),
                localHeaderOffset: localOffset,
                internalAttributes: 0,
                externalAttributes: externalAttr,
                nameBytes: nameBytes,
                comment: Data()
            )
        }

        let declaredSize = UInt64((attrs[.size] as? Int64) ?? 0)
        let wantsDeflate = ZipMethod.forFile(named: url.lastPathComponent) == .deflate && declaredSize > 0
        let method: UInt16 = wantsDeflate ? 8 : 0
        let needsZ64 = declaredSize >= 0xFFFF_FFFF
        let versionNeeded: UInt16 = needsZ64 ? 45 : 20

        var localExtra = Data()
        if needsZ64 {
            appendU16(0x0001, to: &localExtra)
            appendU16(16, to: &localExtra)
            appendU64(0, to: &localExtra)
            appendU64(0, to: &localExtra)
        }

        // Write placeholder Local File Header, stream payload, then patch CRC-32 and sizes.
        var header = Data()
        header.reserveCapacity(30 + nameBytes.count + localExtra.count)
        appendU32(0x0403_4b50, to: &header)
        appendU16(versionNeeded, to: &header)
        appendU16(flags, to: &header)
        appendU16(method, to: &header)
        appendU16(dosTime, to: &header)
        appendU16(dosDate, to: &header)
        appendU32(0, to: &header)  // crc placeholder at +14
        appendU32(0, to: &header)  // compressed size placeholder at +18
        appendU32(0, to: &header)  // uncompressed size placeholder at +22
        appendU16(UInt16(nameBytes.count), to: &header)
        appendU16(UInt16(localExtra.count), to: &header)
        header.append(nameBytes)
        header.append(localExtra)
        try out.write(contentsOf: header)

        let payloadStart = try out.offset()
        var crc: uLong = zlib.crc32(0, nil, 0)
        var uncompTotal: UInt64 = 0
        var compTotal: UInt64 = 0

        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        if method == 0 {
            while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
                data.withUnsafeBytes { raw in
                    if let base = raw.bindMemory(to: Bytef.self).baseAddress {
                        crc = zlib.crc32(crc, base, uInt(raw.count))
                    }
                }
                try out.write(contentsOf: data)
                uncompTotal += UInt64(data.count)
                compTotal += UInt64(data.count)
                try report(Int64(data.count))
            }
        } else {
            var stream = z_stream()
            let initStatus = deflateInit2_(
                &stream,
                Int32(compressionLevel.rawValue),
                Z_DEFLATED,
                -MAX_WBITS,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw ArchiveError.unwritable("Failed to initialize Deflate compressor.")
            }
            defer { deflateEnd(&stream) }

            var outBuf = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let data = (try input.read(upToCount: chunkSize)) ?? Data()
                let isEOF = data.isEmpty
                if !isEOF {
                    data.withUnsafeBytes { raw in
                        if let base = raw.bindMemory(to: Bytef.self).baseAddress {
                            crc = zlib.crc32(crc, base, uInt(raw.count))
                        }
                    }
                    uncompTotal += UInt64(data.count)
                }

                try data.withUnsafeBytes { rawIn in
                    stream.next_in = UnsafeMutablePointer<Bytef>(
                        mutating: rawIn.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(rawIn.count)
                    let flush = isEOF ? Z_FINISH : Z_NO_FLUSH
                    repeat {
                        let writtenChunk: Int = try outBuf.withUnsafeMutableBufferPointer { rawOut in
                            stream.next_out = rawOut.baseAddress
                            stream.avail_out = uInt(rawOut.count)
                            let status = zlib.deflate(&stream, flush)
                            guard status != Z_STREAM_ERROR else {
                                throw ArchiveError.unwritable("Deflate stream error.")
                            }
                            return rawOut.count - Int(stream.avail_out)
                        }
                        if writtenChunk > 0 {
                            try out.write(contentsOf: outBuf[0..<writtenChunk])
                            compTotal += UInt64(writtenChunk)
                        }
                    } while stream.avail_out == 0
                }

                if !isEOF {
                    try report(Int64(data.count))
                } else {
                    break
                }
            }
        }

        let endOffset = try out.offset()
        let crc32Val = UInt32(truncatingIfNeeded: crc)

        // Patch CRC-32 and sizes in the Local File Header.
        try out.seek(toOffset: localOffset + 14)
        var patch = Data()
        appendU32(crc32Val, to: &patch)
        appendU32(needsZ64 ? 0xFFFF_FFFF : UInt32(min(compTotal, 0xFFFF_FFFF)), to: &patch)
        appendU32(needsZ64 ? 0xFFFF_FFFF : UInt32(min(uncompTotal, 0xFFFF_FFFF)), to: &patch)
        try out.write(contentsOf: patch)

        if needsZ64 {
            try out.seek(toOffset: payloadStart - 16)
            var z64Patch = Data()
            appendU64(uncompTotal, to: &z64Patch)
            appendU64(compTotal, to: &z64Patch)
            try out.write(contentsOf: z64Patch)
        }
        try out.seek(toOffset: endOffset)

        return CentralRecord(
            versionMadeBy: 0x031E,
            versionNeeded: versionNeeded,
            flags: flags,
            method: method,
            dosTime: dosTime,
            dosDate: dosDate,
            crc32: crc32Val,
            compressedSize: compTotal,
            uncompressedSize: uncompTotal,
            localHeaderOffset: localOffset,
            internalAttributes: 0,
            externalAttributes: externalAttr,
            nameBytes: nameBytes,
            comment: Data()
        )
    }

    private static func copyBytes(
        from source: FileHandle,
        offset: UInt64,
        length: UInt64,
        to destination: FileHandle,
        reportPayloadOnlyFrom payloadStartDelta: UInt64,
        report: (Int64) throws -> Void
    ) throws {
        try source.seek(toOffset: offset)
        var remaining = length
        var copied: UInt64 = 0
        while remaining > 0 {
            let step = Int(min(UInt64(chunkSize), remaining))
            guard let data = try source.read(upToCount: step), !data.isEmpty else {
                throw ArchiveError.unreadable("Unexpected end of file while copying ZIP entry.")
            }
            try destination.write(contentsOf: data)
            let prev = copied
            copied += UInt64(data.count)
            remaining -= UInt64(data.count)
            if copied > payloadStartDelta {
                let effectiveStart = max(prev, payloadStartDelta)
                try report(Int64(copied - effectiveStart))
            }
        }
    }

    private static func appendCentralHeader(_ rec: CentralRecord, into buffer: inout Data) {
        let needsUncomp64 = rec.uncompressedSize >= 0xFFFF_FFFF
        let needsComp64 = rec.compressedSize >= 0xFFFF_FFFF
        let needsOffset64 = rec.localHeaderOffset >= 0xFFFF_FFFF
        var extra = Data()
        if needsUncomp64 || needsComp64 || needsOffset64 {
            var z64Payload = Data()
            if needsUncomp64 { appendU64(rec.uncompressedSize, to: &z64Payload) }
            if needsComp64 { appendU64(rec.compressedSize, to: &z64Payload) }
            if needsOffset64 { appendU64(rec.localHeaderOffset, to: &z64Payload) }
            appendU16(0x0001, to: &extra)
            appendU16(UInt16(z64Payload.count), to: &extra)
            extra.append(z64Payload)
        }
        let versionNeeded = max(rec.versionNeeded, extra.isEmpty ? UInt16(20) : UInt16(45))

        appendU32(0x0201_4b50, to: &buffer)
        appendU16(rec.versionMadeBy, to: &buffer)
        appendU16(versionNeeded, to: &buffer)
        appendU16(rec.flags, to: &buffer)
        appendU16(rec.method, to: &buffer)
        appendU16(rec.dosTime, to: &buffer)
        appendU16(rec.dosDate, to: &buffer)
        appendU32(rec.crc32, to: &buffer)
        appendU32(needsComp64 ? 0xFFFF_FFFF : UInt32(rec.compressedSize), to: &buffer)
        appendU32(needsUncomp64 ? 0xFFFF_FFFF : UInt32(rec.uncompressedSize), to: &buffer)
        appendU16(UInt16(rec.nameBytes.count), to: &buffer)
        appendU16(UInt16(extra.count), to: &buffer)
        appendU16(UInt16(rec.comment.count), to: &buffer)
        appendU16(0, to: &buffer)  // disk number start
        appendU16(rec.internalAttributes, to: &buffer)
        appendU32(rec.externalAttributes, to: &buffer)
        appendU32(needsOffset64 ? 0xFFFF_FFFF : UInt32(rec.localHeaderOffset), to: &buffer)
        buffer.append(rec.nameBytes)
        buffer.append(extra)
        buffer.append(rec.comment)
    }

    private static func computeCRC32(_ data: Data) -> UInt32 {
        let crc = data.withUnsafeBytes { raw -> uLong in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else {
                return zlib.crc32(0, nil, 0)
            }
            return zlib.crc32(zlib.crc32(0, nil, 0), base, uInt(raw.count))
        }
        return UInt32(truncatingIfNeeded: crc)
    }

    private static func appendU16(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendU32(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendU64(_ value: UInt64, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
