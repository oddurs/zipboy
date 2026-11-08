import Foundation

/// Reads a ZIP archive's Central Directory without unpacking its payloads.
public struct ZipCatalog: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let index: Int
        private let nonUTF8RawName: Data?
        public var rawName: Data { nonUTF8RawName ?? Data(rawPath.utf8) }
        public let rawPath: String
        public let path: String
        public let versionMadeBy: UInt16
        public let versionNeeded: UInt16
        public let flags: UInt16
        public let method: UInt16
        public let rawDosTime: UInt16
        public let rawDosDate: UInt16
        public let modified: Date?
        public let crc32: UInt32
        public let compressedSize: UInt64
        public let uncompressedSize: UInt64
        public let localHeaderOffset: UInt64
        public let internalAttributes: UInt16
        public let externalAttributes: UInt32
        public let extraField: Data
        public let comment: Data
        public let isDirectory: Bool
        public let isSymlink: Bool
        public let isEncrypted: Bool
        public let posixPermissions: Int

        public var usesUTF8Flag: Bool { (flags & (1 << 11)) != 0 }
        public var hasDataDescriptor: Bool { (flags & 0x0008) != 0 }

        public init(
            index: Int,
            rawName: Data? = nil,
            rawPath: String,
            path: String,
            versionMadeBy: UInt16,
            versionNeeded: UInt16,
            flags: UInt16,
            method: UInt16,
            rawDosTime: UInt16,
            rawDosDate: UInt16,
            modified: Date?,
            crc32: UInt32,
            compressedSize: UInt64,
            uncompressedSize: UInt64,
            localHeaderOffset: UInt64,
            internalAttributes: UInt16,
            externalAttributes: UInt32,
            extraField: Data,
            comment: Data,
            isDirectory: Bool,
            isSymlink: Bool,
            isEncrypted: Bool,
            posixPermissions: Int
        ) {
            self.index = index
            if let rawName, rawName != Data(rawPath.utf8) {
                self.nonUTF8RawName = rawName
            } else {
                self.nonUTF8RawName = nil
            }
            self.rawPath = rawPath
            self.path = path
            self.versionMadeBy = versionMadeBy
            self.versionNeeded = versionNeeded
            self.flags = flags
            self.method = method
            self.rawDosTime = rawDosTime
            self.rawDosDate = rawDosDate
            self.modified = modified
            self.crc32 = crc32
            self.compressedSize = compressedSize
            self.uncompressedSize = uncompressedSize
            self.localHeaderOffset = localHeaderOffset
            self.internalAttributes = internalAttributes
            self.externalAttributes = externalAttributes
            self.extraField = extraField
            self.comment = comment
            self.isDirectory = isDirectory
            self.isSymlink = isSymlink
            self.isEncrypted = isEncrypted
            self.posixPermissions = posixPermissions
        }
    }

    public let entries: [Entry]
    public let skipped: [String]
    public let comment: Data
    public let centralDirectoryOffset: UInt64
    public let centralDirectorySize: UInt64
    public let detectedEncoding: TextEncoding

    public var isEncrypted: Bool { entries.contains(where: \.isEncrypted) }

    /// Reads the Central Directory of the ZIP archive at `url`.
    public static func read(from url: URL, encoding: TextEncoding = .auto) throws -> ZipCatalog {
        let ext = url.pathExtension.lowercased()
        if ext != "zip" {
            guard !Archive.isSplitArchive(url) else {
                throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
            }
        } else {
            let base = url.deletingPathExtension().path
            let fm = FileManager.default
            guard !fm.fileExists(atPath: base + ".z01"), !fm.fileExists(atPath: base + ".Z01") else {
                throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
            }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else {
            throw ArchiveError.unreadable("The ZIP archive is truncated (smaller than 22 bytes).")
        }

        let maxTail: UInt64 = min(fileSize, 65_535 + 22 + 20)
        let tailStart = fileSize - maxTail
        try handle.seek(toOffset: tailStart)
        let tail = try handle.readToEnd() ?? Data()

        guard let eocdPos = findEOCD(in: tail) else {
            throw ArchiveError.unreadable("End of Central Directory record not found.")
        }
        let eocdFileOffset = tailStart + UInt64(eocdPos)
        let diskNumber = readU16(tail, eocdPos + 4)
        let cdDisk = readU16(tail, eocdPos + 6)
        guard diskNumber == 0 && cdDisk == 0 else {
            throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
        }

        var totalEntries = UInt64(readU16(tail, eocdPos + 10))
        var cdSize = UInt64(readU32(tail, eocdPos + 12))
        var cdOffset = UInt64(readU32(tail, eocdPos + 16))
        let commentLen = Int(readU16(tail, eocdPos + 20))
        guard eocdPos + 22 + commentLen <= tail.count else {
            throw ArchiveError.unreadable("Truncated ZIP archive comment.")
        }
        let archiveComment = Data(tail[(eocdPos + 22)..<(eocdPos + 22 + commentLen)])

        var locatorOffset: UInt64?
        if eocdPos >= 20, readU32(tail, eocdPos - 20) == 0x0706_4b50 {
            let loc = tailStart + UInt64(eocdPos - 20)
            locatorOffset = loc
            let z64Disk = readU32(tail, eocdPos - 16)
            let totalDisks = readU32(tail, eocdPos - 4)
            guard z64Disk == 0 && totalDisks <= 1 else {
                throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
            }
            let z64Offset = readU64(tail, eocdPos - 12)
            // Every offset below comes from the file; compare by subtraction so a hostile value can't overflow.
            guard loc >= 56, z64Offset <= loc - 56 else {
                throw ArchiveError.unreadable("Zip64 End of Central Directory offset is out of bounds.")
            }
            try handle.seek(toOffset: z64Offset)
            guard let z64 = try handle.read(upToCount: 56), z64.count == 56,
                readU32(z64, 0) == 0x0606_4b50
            else {
                throw ArchiveError.unreadable("Corrupt Zip64 End of Central Directory record.")
            }
            guard readU32(z64, 16) == 0 && readU32(z64, 20) == 0 else {
                throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
            }
            totalEntries = readU64(z64, 32)
            cdSize = readU64(z64, 40)
            cdOffset = readU64(z64, 48)
        }

        let cdUpperBound = locatorOffset ?? eocdFileOffset
        guard cdOffset <= cdUpperBound,
            cdSize <= cdUpperBound - cdOffset,
            let cdByteCount = Int(exactly: cdSize)
        else {
            throw ArchiveError.unreadable("Central Directory bounds overlap or exceed the archive size.")
        }

        try handle.seek(toOffset: cdOffset)
        let cdData = (try handle.read(upToCount: cdByteCount)) ?? Data()
        guard UInt64(cdData.count) == cdSize else {
            throw ArchiveError.unreadable("Truncated Central Directory.")
        }

        struct DeferredRecord {
            let slot: Int
            let index: Int
            let rawName: Data
            let extraField: Data
            let comment: Data
            let versionMadeBy: UInt16
            let versionNeeded: UInt16
            let flags: UInt16
            let method: UInt16
            let dosTime: UInt16
            let dosDate: UInt16
            let modDate: Date?
            let crc32: UInt32
            let compressedSize: UInt64
            let uncompressedSize: UInt64
            let localHeaderOffset: UInt64
            let internalAttributes: UInt16
            let externalAttributes: UInt32
        }

        var entries: [Entry] = []
        entries.reserveCapacity(Int(min(totalEntries, 131_072)))
        var skipped: [String] = []
        var unflaggedNonASCII: [Data] = []
        var deferredRecords: [DeferredRecord] = []
        var alreadyOrdered = true
        var prevOffset: UInt64 = 0
        var prevEnd: UInt64 = 0
        var cursor = 0
        var index = 0
        let emptyData = Data()
        let cdBaseIndex = cdData.startIndex
        let calendar = Calendar(identifier: .gregorian)
        var dateCache: [UInt32: Date] = [:]
        var lastDosKey: UInt32 = .max
        var lastDosDate: Date? = nil

        try cdData.withUnsafeBytes { rawBuffer in
            let cdCount = rawBuffer.count
            guard let cdBase = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            while cursor < cdCount {
                guard cursor + 46 <= cdCount else {
                    throw ArchiveError.unreadable("Truncated Central Directory entry header.")
                }
                guard loadU32(rawBuffer, cursor) == 0x0201_4b50 else {
                    throw ArchiveError.unreadable("Invalid Central Directory entry signature.")
                }
                let versionMadeBy = loadU16(rawBuffer, cursor + 4)
                let versionNeeded = loadU16(rawBuffer, cursor + 6)
                let flags = loadU16(rawBuffer, cursor + 8)
                let method = loadU16(rawBuffer, cursor + 10)
                let dosTime = loadU16(rawBuffer, cursor + 12)
                let dosDate = loadU16(rawBuffer, cursor + 14)
                let crc = loadU32(rawBuffer, cursor + 16)
                var compSize = UInt64(loadU32(rawBuffer, cursor + 20))
                var uncompSize = UInt64(loadU32(rawBuffer, cursor + 24))
                let nameLen = Int(loadU16(rawBuffer, cursor + 28))
                let extraLen = Int(loadU16(rawBuffer, cursor + 30))
                let entryCommentLen = Int(loadU16(rawBuffer, cursor + 32))
                var diskStart = UInt32(loadU16(rawBuffer, cursor + 34))
                let internalAttr = loadU16(rawBuffer, cursor + 36)
                let externalAttr = loadU32(rawBuffer, cursor + 38)
                var localOffset = UInt64(loadU32(rawBuffer, cursor + 42))

                let nameStart = cursor + 46
                let extraStart = nameStart + nameLen
                let extraEnd = extraStart + extraLen
                let headerEnd = extraEnd + entryCommentLen
                guard headerEnd <= cdCount else {
                    throw ArchiveError.unreadable("Central Directory entry extends past the directory.")
                }

                var unicodeName: String?
                if extraLen > 0 {
                    var ePos = extraStart
                    while ePos + 4 <= extraEnd {
                        let tag = loadU16(rawBuffer, ePos)
                        let size = Int(loadU16(rawBuffer, ePos + 2))
                        let fieldEnd = ePos + 4 + size
                        guard fieldEnd <= extraEnd else {
                            throw ArchiveError.unreadable("Malformed extra field in Central Directory.")
                        }
                        if tag == 0x0001 {
                            var fPos = ePos + 4
                            if uncompSize == 0xFFFF_FFFF, fPos + 8 <= fieldEnd {
                                uncompSize = loadU64(rawBuffer, fPos)
                                fPos += 8
                            }
                            if compSize == 0xFFFF_FFFF, fPos + 8 <= fieldEnd {
                                compSize = loadU64(rawBuffer, fPos)
                                fPos += 8
                            }
                            if localOffset == 0xFFFF_FFFF, fPos + 8 <= fieldEnd {
                                localOffset = loadU64(rawBuffer, fPos)
                                fPos += 8
                            }
                            if diskStart == 0xFFFF, fPos + 4 <= fieldEnd {
                                diskStart = loadU32(rawBuffer, fPos)
                            }
                        } else if tag == 0x7075, size >= 5 {
                            let version = cdBase[ePos + 4]
                            if version == 1 {
                                let extraPathBytes = UnsafeBufferPointer(
                                    start: cdBase.advanced(by: ePos + 9), count: fieldEnd - (ePos + 9))
                                unicodeName = String(decoding: extraPathBytes, as: UTF8.self)
                            }
                        }
                        ePos = fieldEnd
                    }
                }

                guard diskStart == 0 else {
                    throw ArchiveError.unreadable("Multi-disk split ZIP archives require all parts merged.")
                }

                guard cdOffset >= 30, localOffset <= cdOffset - 30,
                    compSize <= cdOffset - 30 - localOffset
                else {
                    throw ArchiveError.unreadable("Entry local header or payload extends into the Central Directory.")
                }

                let entryEnd = localOffset + 30 + UInt64(nameLen) + compSize
                if index > 0 {
                    if localOffset < prevOffset {
                        alreadyOrdered = false
                    } else if alreadyOrdered && prevEnd > localOffset {
                        throw ArchiveError.unreadable("Overlapping local file entries in ZIP archive.")
                    }
                }
                prevOffset = localOffset
                prevEnd = entryEnd

                let dosKey = (UInt32(dosDate) << 16) | UInt32(dosTime)
                let modDate: Date?
                if dosKey == lastDosKey {
                    modDate = lastDosDate
                } else {
                    modDate = Self.dosDate(
                        date: dosDate, time: dosTime, calendar: calendar, cache: &dateCache)
                    lastDosKey = dosKey
                    lastDosDate = modDate
                }

                let extraField =
                    extraLen == 0
                    ? emptyData
                    : cdData[(cdBaseIndex + extraStart)..<(cdBaseIndex + extraEnd)]
                let comment =
                    entryCommentLen == 0
                    ? emptyData
                    : cdData[(cdBaseIndex + extraEnd)..<(cdBaseIndex + headerEnd)]

                let namePtr = cdBase.advanced(by: nameStart)
                let (hasHighByte, cleanASCII) = classifyASCII(namePtr, count: nameLen)

                let entryIdx = index
                index += 1
                cursor = headerEnd

                if unicodeName == nil, !hasHighByte, cleanASCII {
                    let cleanName = String(
                        decoding: UnsafeBufferPointer(start: namePtr, count: nameLen), as: UTF8.self)
                    let unixMode = Int((externalAttr >> 16) & 0xFFFF)
                    let unixType = unixMode & 0o170000
                    let isDir =
                        unixType == 0o040000
                        || ((versionMadeBy >> 8) == 0 && (externalAttr & 0x10) != 0)
                    let isSymlink = unixType == 0o120000
                    let perms = (unixMode & 0o7777) != 0 ? (unixMode & 0o7777) : (isDir ? 0o755 : 0o644)
                    let isEncrypted = (flags & 0x0001) != 0 || method == 99
                    entries.append(
                        Entry(
                            index: entryIdx,
                            rawName: nil,
                            rawPath: cleanName,
                            path: cleanName,
                            versionMadeBy: versionMadeBy,
                            versionNeeded: versionNeeded,
                            flags: flags,
                            method: method,
                            rawDosTime: dosTime,
                            rawDosDate: dosDate,
                            modified: modDate,
                            crc32: crc,
                            compressedSize: compSize,
                            uncompressedSize: uncompSize,
                            localHeaderOffset: localOffset,
                            internalAttributes: internalAttr,
                            externalAttributes: externalAttr,
                            extraField: extraField,
                            comment: comment,
                            isDirectory: isDir,
                            isSymlink: isSymlink,
                            isEncrypted: isEncrypted,
                            posixPermissions: perms
                        ))
                    continue
                }

                let rawName = cdData[(cdBaseIndex + nameStart)..<(cdBaseIndex + extraStart)]
                let utf8Flag = (flags & (1 << 11)) != 0
                if !utf8Flag, unicodeName == nil, hasHighByte {
                    unflaggedNonASCII.append(rawName)
                    if encoding == .auto {
                        let slot = entries.count
                        entries.append(
                            Entry(
                                index: entryIdx,
                                rawName: rawName,
                                rawPath: "",
                                path: "",
                                versionMadeBy: versionMadeBy,
                                versionNeeded: versionNeeded,
                                flags: flags,
                                method: method,
                                rawDosTime: dosTime,
                                rawDosDate: dosDate,
                                modified: modDate,
                                crc32: crc,
                                compressedSize: compSize,
                                uncompressedSize: uncompSize,
                                localHeaderOffset: localOffset,
                                internalAttributes: internalAttr,
                                externalAttributes: externalAttr,
                                extraField: extraField,
                                comment: comment,
                                isDirectory: false,
                                isSymlink: false,
                                isEncrypted: false,
                                posixPermissions: 0o644
                            ))
                        deferredRecords.append(
                            DeferredRecord(
                                slot: slot,
                                index: entryIdx,
                                rawName: rawName,
                                extraField: extraField,
                                comment: comment,
                                versionMadeBy: versionMadeBy,
                                versionNeeded: versionNeeded,
                                flags: flags,
                                method: method,
                                dosTime: dosTime,
                                dosDate: dosDate,
                                modDate: modDate,
                                crc32: crc,
                                compressedSize: compSize,
                                uncompressedSize: uncompSize,
                                localHeaderOffset: localOffset,
                                internalAttributes: internalAttr,
                                externalAttributes: externalAttr
                            ))
                        continue
                    }
                }

                let decodedName: String
                if let unicodeName {
                    decodedName = unicodeName
                } else if !hasHighByte {
                    decodedName = String(
                        decoding: UnsafeBufferPointer(start: namePtr, count: nameLen), as: UTF8.self)
                } else {
                    decodedName = encoding.decode(rawName, utf8Flagged: utf8Flag)
                }
                guard let cleanPath = EntryPath.sanitized(decodedName) else {
                    skipped.append(decodedName)
                    continue
                }
                let unixMode = Int((externalAttr >> 16) & 0xFFFF)
                let unixType = unixMode & 0o170000
                let lastByte = decodedName.utf8.last
                let isDir =
                    lastByte == 0x2F
                    || lastByte == 0x5C
                    || unixType == 0o040000
                    || ((versionMadeBy >> 8) == 0 && (externalAttr & 0x10) != 0)
                let isSymlink = unixType == 0o120000
                let perms = (unixMode & 0o7777) != 0 ? (unixMode & 0o7777) : (isDir ? 0o755 : 0o644)
                let isEncrypted = (flags & 0x0001) != 0 || method == 99
                entries.append(
                    Entry(
                        index: entryIdx,
                        rawName: rawName,
                        rawPath: decodedName,
                        path: cleanPath,
                        versionMadeBy: versionMadeBy,
                        versionNeeded: versionNeeded,
                        flags: flags,
                        method: method,
                        rawDosTime: dosTime,
                        rawDosDate: dosDate,
                        modified: modDate,
                        crc32: crc,
                        compressedSize: compSize,
                        uncompressedSize: uncompSize,
                        localHeaderOffset: localOffset,
                        internalAttributes: internalAttr,
                        externalAttributes: externalAttr,
                        extraField: extraField,
                        comment: comment,
                        isDirectory: isDir,
                        isSymlink: isSymlink,
                        isEncrypted: isEncrypted,
                        posixPermissions: perms
                    ))
            }
        }

        guard UInt64(index) == totalEntries else {
            throw ArchiveError.unreadable(
                "Central Directory entry count (\(index)) does not match header (\(totalEntries)).")
        }

        let resolvedEncoding: TextEncoding =
            encoding == .auto
            ? (unflaggedNonASCII.isEmpty ? .utf8 : TextEncoding.detect(for: unflaggedNonASCII)) : encoding

        if !deferredRecords.isEmpty {
            var removedSlots: Set<Int> = []
            for record in deferredRecords {
                let utf8Flag = (record.flags & (1 << 11)) != 0
                let decodedName = resolvedEncoding.decode(record.rawName, utf8Flagged: utf8Flag)
                guard let cleanPath = EntryPath.sanitized(decodedName) else {
                    skipped.append(decodedName)
                    removedSlots.insert(record.slot)
                    continue
                }
                let unixMode = Int((record.externalAttributes >> 16) & 0xFFFF)
                let unixType = unixMode & 0o170000
                let lastByte = decodedName.utf8.last
                let isDir =
                    lastByte == 0x2F
                    || lastByte == 0x5C
                    || unixType == 0o040000
                    || ((record.versionMadeBy >> 8) == 0 && (record.externalAttributes & 0x10) != 0)
                let isSymlink = unixType == 0o120000
                let perms = (unixMode & 0o7777) != 0 ? (unixMode & 0o7777) : (isDir ? 0o755 : 0o644)
                let isEncrypted = (record.flags & 0x0001) != 0 || record.method == 99
                entries[record.slot] = Entry(
                    index: record.index,
                    rawName: record.rawName,
                    rawPath: decodedName,
                    path: cleanPath,
                    versionMadeBy: record.versionMadeBy,
                    versionNeeded: record.versionNeeded,
                    flags: record.flags,
                    method: record.method,
                    rawDosTime: record.dosTime,
                    rawDosDate: record.dosDate,
                    modified: record.modDate,
                    crc32: record.crc32,
                    compressedSize: record.compressedSize,
                    uncompressedSize: record.uncompressedSize,
                    localHeaderOffset: record.localHeaderOffset,
                    internalAttributes: record.internalAttributes,
                    externalAttributes: record.externalAttributes,
                    extraField: record.extraField,
                    comment: record.comment,
                    isDirectory: isDir,
                    isSymlink: isSymlink,
                    isEncrypted: isEncrypted,
                    posixPermissions: perms
                )
            }
            if !removedSlots.isEmpty {
                entries = entries.enumerated().compactMap { removedSlots.contains($0.offset) ? nil : $0.element }
            }
        }

        if !alreadyOrdered && entries.count > 1 {
            let byOffset = entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
            for i in 0..<(byOffset.count - 1) {
                let current = byOffset[i]
                let next = byOffset[i + 1]
                let minCurrentEnd =
                    current.localHeaderOffset + 30 + UInt64(current.rawPath.utf8.count) + current.compressedSize
                if minCurrentEnd > next.localHeaderOffset {
                    throw ArchiveError.unreadable("Overlapping local file entries in ZIP archive.")
                }
            }
        }

        return ZipCatalog(
            entries: entries,
            skipped: skipped,
            comment: archiveComment,
            centralDirectoryOffset: cdOffset,
            centralDirectorySize: cdSize,
            detectedEncoding: resolvedEncoding
        )
    }

    /// Returns the offset and length of `entry`'s compressed payload inside `handle`, after verifying
    /// its Local File Header.
    public static func payloadRange(in handle: FileHandle, for entry: Entry) throws -> (offset: UInt64, length: UInt64)
    {
        try handle.seek(toOffset: entry.localHeaderOffset)
        guard let local = try handle.read(upToCount: 30), local.count == 30,
            readU32(local, 0) == 0x0403_4b50
        else {
            throw ArchiveError.unreadable("Corrupt Local File Header for “\(entry.path)”.")
        }
        let localNameLen = UInt64(readU16(local, 26))
        let localExtraLen = UInt64(readU16(local, 28))
        let dataOffset = entry.localHeaderOffset + 30 + localNameLen + localExtraLen
        return (dataOffset, entry.compressedSize)
    }

    private static func findEOCD(in tail: Data) -> Int? {
        guard tail.count >= 22 else { return nil }
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if readU32(tail, i) == 0x0605_4b50 {
                let commentLen = Int(readU16(tail, i + 20))
                if i + 22 + commentLen == tail.count {
                    return i
                }
            }
        }
        for i in stride(from: tail.count - 22, through: 0, by: -1) where readU32(tail, i) == 0x0605_4b50 {
            return i
        }
        return nil
    }

    private static func dosDate(
        date: UInt16, time: UInt16, calendar: Calendar, cache: inout [UInt32: Date]
    ) -> Date? {
        guard date != 0 || time != 0 else { return nil }
        let key = (UInt32(date) << 16) | UInt32(time)
        if let cached = cache[key] { return cached }
        var comps = DateComponents()
        comps.year = Int((date >> 9) & 0x7F) + 1980
        comps.month = max(1, Int((date >> 5) & 0x0F))
        comps.day = max(1, Int(date & 0x1F))
        comps.hour = Int((time >> 11) & 0x1F)
        comps.minute = Int((time >> 5) & 0x3F)
        comps.second = Int((time & 0x1F) * 2)
        if let resolved = calendar.date(from: comps) {
            cache[key] = resolved
            return resolved
        }
        return nil
    }

    /// Converts a `Date` into MS-DOS date and time 16-bit words.
    public static func encodeDosDate(_ date: Date?) -> (date: UInt16, time: UInt16) {
        guard let date else { return (0, 0) }
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(max(1980, min(2107, comps.year ?? 1980)) - 1980)
        let month = UInt16(max(1, min(12, comps.month ?? 1)))
        let day = UInt16(max(1, min(31, comps.day ?? 1)))
        let hour = UInt16(max(0, min(23, comps.hour ?? 0)))
        let minute = UInt16(max(0, min(59, comps.minute ?? 0)))
        let second = UInt16(max(0, min(59, comps.second ?? 0)) / 2)
        let dosDate = (year << 9) | (month << 5) | day
        let dosTime = (hour << 11) | (minute << 5) | second
        return (dosDate, dosTime)
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        let lo = UInt64(readU32(data, offset))
        let hi = UInt64(readU32(data, offset + 4))
        return lo | (hi << 32)
    }

    private static func loadU16(_ buffer: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
    }

    private static func loadU32(_ buffer: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
    }

    private static func loadU64(_ buffer: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian
    }

    private static func classifyASCII(_ base: UnsafePointer<UInt8>, count n: Int) -> (hasHighByte: Bool, isClean: Bool)
    {
        guard n > 0 else { return (false, false) }
        var isClean = base[0] != 0x2F && base[n - 1] != 0x2F
        var start = 0
        var i = 0
        while i < n {
            let b = base[i]
            if b >= 0x80 {
                return (true, false)
            }
            if isClean {
                if b == 0x5C {
                    isClean = false
                } else if b == 0x2F {
                    if !isCleanSegment(base, start: start, len: i - start) {
                        isClean = false
                    }
                    start = i + 1
                }
            }
            i += 1
        }
        if isClean, !isCleanSegment(base, start: start, len: n - start) {
            isClean = false
        }
        return (false, isClean)
    }

    private static func isCleanSegment(_ base: UnsafePointer<UInt8>, start: Int, len: Int) -> Bool {
        if len == 0 { return false }
        let b0 = base[start]
        if b0 == 0x2E {
            if len == 1 { return false }
            let b1 = base[start + 1]
            if b1 == 0x5F { return false }
            if len == 2 && b1 == 0x2E { return false }
            if len == 9
                && b1 == 0x44 && base[start + 2] == 0x53 && base[start + 3] == 0x5F
                && base[start + 4] == 0x53 && base[start + 5] == 0x74 && base[start + 6] == 0x6F
                && base[start + 7] == 0x72 && base[start + 8] == 0x65
            {
                return false
            }
        } else if len == 8 && b0 == 0x5F
            && base[start + 1] == 0x5F && base[start + 2] == 0x4D && base[start + 3] == 0x41
            && base[start + 4] == 0x43 && base[start + 5] == 0x4F && base[start + 6] == 0x53
            && base[start + 7] == 0x58
        {
            return false
        }
        return true
    }
}
