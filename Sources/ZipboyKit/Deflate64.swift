import Foundation
import zlib

/// Decodes ZIP entries compressed with Deflate64 (method 9), which Windows Explorer writes for large
/// files and libarchive cannot read on its own. Deflate64 is RFC 1951 Deflate widened to a 64 KB
/// sliding window (distance codes 30 and 31 take 14 extra bits) and a 16-bit extra field on length
/// code 285.
enum Deflate64 {
    static let method: UInt16 = 9
    private static let windowSize = 65_536
    private static let windowMask = windowSize - 1

    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 3,
    ]
    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 16,
    ]
    private static let distBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 32769, 49153,
    ]
    private static let distExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14,
    ]
    private static let codeOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    struct EntrySlice {
        var dataOffset: UInt64
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var crc32: UInt32
    }

    /// Finds the `occurrence`-th Deflate64 entry named `rawName` in `zipURL`, decodes it into `out`,
    /// checks its CRC-32 and uncompressed length, and updates `budget` and `report` as chunks land.
    /// Before each window is written, `admit` hears its size and the compressed bytes read so far, and
    /// throws to stop a bomb; an entry that outgrows its declared size stops at that point too.
    static func extract(
        named rawName: String, occurrence: Int, from zipURL: URL, encoding: TextEncoding, to out: FileHandle,
        budget: inout Int64?, capacity: () -> Int64?, report: () throws -> Void,
        admit: (_ bytes: Int64, _ consumed: UInt64) throws -> Void
    ) throws {
        let slice = try locateEntry(named: rawName, occurrence: occurrence, in: zipURL, encoding: encoding)
        let reader = try FileHandle(forReadingFrom: zipURL)
        defer { try? reader.close() }
        try reader.seek(toOffset: slice.dataOffset)

        var bits = BitReader(handle: reader, remaining: slice.compressedSize)
        var window = [UInt8](repeating: 0, count: windowSize)
        var winPos = 0
        var totalOut: UInt64 = 0
        var crc: uLong = zlib.crc32(0, nil, 0)

        func flush(_ count: Int) throws {
            guard count > 0 else { return }
            guard UInt64(count) <= slice.uncompressedSize - totalOut else {
                throw ArchiveError.suspiciousArchive(
                    "The entry “\(rawName)” expanded past its declared size and was stopped.")
            }
            try admit(Int64(count), slice.compressedSize - bits.remaining)
            if let known = budget, Int64(count) > known {
                let fresh = capacity() ?? known
                budget = fresh
                if Int64(count) > fresh {
                    throw ArchiveError.noSpace(
                        needed: max(Int64(slice.uncompressedSize), Int64(totalOut) + Int64(count)),
                        available: fresh)
                }
            }
            let chunk = Data(window[0..<count])
            do {
                try out.write(contentsOf: chunk)
            } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
                throw ArchiveError.noSpace(
                    needed: max(Int64(slice.uncompressedSize), Int64(totalOut) + Int64(count)),
                    available: capacity() ?? 0)
            }
            chunk.withUnsafeBytes { ptr in
                if let base = ptr.bindMemory(to: Bytef.self).baseAddress {
                    crc = zlib.crc32(crc, base, uInt(count))
                }
            }
            totalOut += UInt64(count)
            budget = budget.map { $0 - Int64(count) }
            try report()
        }

        var finalBlock = false
        while !finalBlock {
            finalBlock = try bits.readBits(1) == 1
            let blockType = try bits.readBits(2)
            switch blockType {
            case 0:
                bits.alignToByte()
                let len = try bits.readBits(16)
                let nlen = try bits.readBits(16)
                guard (len ^ nlen) == 0xFFFF else {
                    throw ArchiveError.unreadable("Corrupt Deflate64 stored block.")
                }
                for _ in 0..<len {
                    let b = try bits.readByte()
                    window[winPos] = b
                    winPos += 1
                    if winPos == windowSize {
                        try flush(windowSize)
                        winPos = 0
                    }
                }
            case 1, 2:
                let (litTree, distTree) =
                    blockType == 1 ? (Huffman.fixedLit, Huffman.fixedDist) : try readDynamicTrees(&bits)
                while true {
                    let sym = try litTree.decode(&bits)
                    if sym < 256 {
                        window[winPos] = UInt8(sym)
                        winPos += 1
                        if winPos == windowSize {
                            try flush(windowSize)
                            winPos = 0
                        }
                    } else if sym == 256 {
                        break
                    } else {
                        let lenIdx = sym - 257
                        guard lenIdx < lengthBase.count else {
                            throw ArchiveError.unreadable("Invalid Deflate64 length code.")
                        }
                        let length = lengthBase[lenIdx] + (try bits.readBits(lengthExtra[lenIdx]))
                        let distSym = try distTree.decode(&bits)
                        guard distSym < distBase.count else {
                            throw ArchiveError.unreadable("Invalid Deflate64 distance code.")
                        }
                        let distance = distBase[distSym] + (try bits.readBits(distExtra[distSym]))
                        let availableHistory = totalOut + UInt64(winPos)
                        guard distance > 0, UInt64(distance) <= availableHistory else {
                            throw ArchiveError.unreadable("Corrupt Deflate64 match distance.")
                        }
                        for _ in 0..<length {
                            let src = (winPos - distance) & windowMask
                            let b = window[src]
                            window[winPos] = b
                            winPos += 1
                            if winPos == windowSize {
                                try flush(windowSize)
                                winPos = 0
                            }
                        }
                    }
                }
            default:
                throw ArchiveError.unreadable("Invalid Deflate64 block type.")
            }
        }
        if winPos > 0 { try flush(winPos) }

        guard totalOut == slice.uncompressedSize else {
            throw ArchiveError.suspiciousArchive(
                "The entry “\(rawName)” ended at \(totalOut) bytes instead of its declared \(slice.uncompressedSize) bytes."
            )
        }
        guard UInt32(truncatingIfNeeded: crc) == slice.crc32 else {
            throw ArchiveError.unreadable("Corrupt Deflate64 data.")
        }
    }

    private static func readDynamicTrees(_ bits: inout BitReader) throws -> (Huffman, Huffman) {
        let hlit = try bits.readBits(5) + 257
        let hdist = try bits.readBits(5) + 1
        let hclen = try bits.readBits(4) + 4
        guard hlit <= 286, hdist <= 32 else {
            throw ArchiveError.unreadable("Invalid Deflate64 dynamic header.")
        }
        var codeLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengths[codeOrder[i]] = try bits.readBits(3)
        }
        let codeTree = try Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        lengths.reserveCapacity(hlit + hdist)
        while lengths.count < hlit + hdist {
            let sym = try codeTree.decode(&bits)
            switch sym {
            case 0...15:
                lengths.append(sym)
            case 16:
                guard let prev = lengths.last else {
                    throw ArchiveError.unreadable("Invalid Deflate64 code length repeat.")
                }
                let repeatCount = try bits.readBits(2) + 3
                lengths.append(contentsOf: repeatElement(prev, count: repeatCount))
            case 17:
                let repeatCount = try bits.readBits(3) + 3
                lengths.append(contentsOf: repeatElement(0, count: repeatCount))
            case 18:
                let repeatCount = try bits.readBits(7) + 11
                lengths.append(contentsOf: repeatElement(0, count: repeatCount))
            default:
                throw ArchiveError.unreadable("Invalid Deflate64 code length symbol.")
            }
        }
        guard lengths.count == hlit + hdist else {
            throw ArchiveError.unreadable("Corrupt Deflate64 Huffman table.")
        }
        let litTree = try Huffman(lengths: Array(lengths[0..<hlit]))
        let distTree = try Huffman(lengths: Array(lengths[hlit..<(hlit + hdist)]))
        return (litTree, distTree)
    }

    /// Reads the Central Directory of `zipURL` to locate the `occurrence`-th Deflate64 entry whose
    /// stored name, decoded with `encoding` and its UTF-8 flag as `Archive.name(of:in:)` does, matches `rawName`.
    private static func locateEntry(
        named rawName: String, occurrence: Int, in zipURL: URL, encoding: TextEncoding
    ) throws -> EntrySlice {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ArchiveError.unreadable("Truncated ZIP archive.") }

        let tailSize = min(fileSize, 65_557)
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try handle.readToEnd() ?? Data()

        var eocdPos: Int?
        if tail.count >= 22 {
            for idx in stride(from: tail.count - 22, through: 0, by: -1)
            where tail.u32(at: idx) == 0x0605_4B50 {
                eocdPos = idx
                break
            }
        }
        guard let eocdPos else { throw ArchiveError.unreadable("Missing ZIP central directory.") }

        var cdOffset = UInt64(tail.u32(at: eocdPos + 16))
        var cdSize = UInt64(tail.u32(at: eocdPos + 12))

        // Zip64 End of Central Directory Locator sits 20 bytes before EOCD.
        if eocdPos >= 20, tail.u32(at: eocdPos - 20) == 0x0706_4B50 {
            let zip64EOCDOffset = tail.u64(at: eocdPos - 12)
            try handle.seek(toOffset: zip64EOCDOffset)
            if let z64 = try handle.read(upToCount: 56), z64.count == 56, z64.u32(at: 0) == 0x0606_4B50 {
                cdSize = z64.u64(at: 40)
                cdOffset = z64.u64(at: 48)
            }
        }

        guard cdOffset <= fileSize, cdSize <= fileSize - cdOffset else {
            throw ArchiveError.unreadable("Corrupt ZIP central directory.")
        }
        try handle.seek(toOffset: cdOffset)
        let cd = try handle.read(upToCount: Int(cdSize)) ?? Data()

        var pos = 0
        var seen = 0
        while pos + 46 <= cd.count, cd.u32(at: pos) == 0x0201_4B50 {
            let utf8Flagged = cd.u16(at: pos + 8) & (1 << 11) != 0
            let entryMethod = cd.u16(at: pos + 10)
            let crc = cd.u32(at: pos + 16)
            var compSize = UInt64(cd.u32(at: pos + 20))
            var uncompSize = UInt64(cd.u32(at: pos + 24))
            let nameLen = Int(cd.u16(at: pos + 28))
            let extraLen = Int(cd.u16(at: pos + 30))
            let commentLen = Int(cd.u16(at: pos + 32))
            var localOffset = UInt64(cd.u32(at: pos + 42))

            let headerEnd = pos + 46 + nameLen + extraLen + commentLen
            guard headerEnd <= cd.count else { break }

            let nameData = cd.subdata(in: (pos + 46)..<(pos + 46 + nameLen))
            let extraData = cd.subdata(in: (pos + 46 + nameLen)..<(pos + 46 + nameLen + extraLen))

            // Parse Zip64 extended information extra field (0x0001) when 32-bit fields are 0xFFFFFFFF.
            var ePos = 0
            while ePos + 4 <= extraData.count {
                let tag = extraData.u16(at: ePos)
                let size = Int(extraData.u16(at: ePos + 2))
                guard ePos + 4 + size <= extraData.count else { break }
                if tag == 0x0001 {
                    var cursor = ePos + 4
                    if uncompSize == 0xFFFF_FFFF, cursor + 8 <= ePos + 4 + size {
                        uncompSize = extraData.u64(at: cursor)
                        cursor += 8
                    }
                    if compSize == 0xFFFF_FFFF, cursor + 8 <= ePos + 4 + size {
                        compSize = extraData.u64(at: cursor)
                        cursor += 8
                    }
                    if localOffset == 0xFFFF_FFFF, cursor + 8 <= ePos + 4 + size {
                        localOffset = extraData.u64(at: cursor)
                    }
                }
                ePos += 4 + size
            }

            let entryName = encoding.decode(nameData, utf8Flagged: utf8Flagged)
            if entryMethod == method, entryName == rawName {
                if seen == occurrence {
                    guard fileSize >= 30, localOffset <= fileSize - 30 else {
                        throw ArchiveError.unreadable("Corrupt ZIP local file header.")
                    }
                    try handle.seek(toOffset: localOffset)
                    guard let local = try handle.read(upToCount: 30), local.count == 30,
                        local.u32(at: 0) == 0x0403_4B50
                    else {
                        throw ArchiveError.unreadable("Corrupt ZIP local file header.")
                    }
                    let localNameLen = UInt64(local.u16(at: 26))
                    let localExtraLen = UInt64(local.u16(at: 28))
                    let dataOffset = localOffset + 30 + localNameLen + localExtraLen
                    guard dataOffset <= fileSize, compSize <= fileSize - dataOffset else {
                        throw ArchiveError.unreadable("Truncated Deflate64 entry.")
                    }
                    let localFlags = local.u16(at: 6)
                    if localFlags & 0x0008 == 0 {
                        let localComp = local.u32(at: 18)
                        let localUncomp = local.u32(at: 22)
                        let expectedComp = UInt32(min(compSize, 0xFFFF_FFFF))
                        let expectedUncomp = UInt32(min(uncompSize, 0xFFFF_FFFF))
                        if localComp != expectedComp || localUncomp != expectedUncomp {
                            throw ArchiveError.suspiciousArchive(
                                "The entry “\(rawName)” declares different sizes in its local header and central directory."
                            )
                        }
                    }
                    return EntrySlice(
                        dataOffset: dataOffset, compressedSize: compSize, uncompressedSize: uncompSize, crc32: crc)
                }
                seen += 1
            }
            pos = headerEnd
        }
        throw ArchiveError.unreadable("Unsupported ZIP compression method (9: deflation-64-bit)")
    }

    private struct BitReader {
        let handle: FileHandle
        var remaining: UInt64
        var buffer = Data()
        var index = 0
        var bitBuf: UInt64 = 0
        var bitCount = 0

        init(handle: FileHandle, remaining: UInt64) {
            self.handle = handle
            self.remaining = remaining
        }

        mutating func readByte() throws -> UInt8 {
            if bitCount >= 8 {
                let b = UInt8(truncatingIfNeeded: bitBuf & 0xFF)
                bitBuf >>= 8
                bitCount -= 8
                return b
            }
            if index >= buffer.count {
                guard remaining > 0 else {
                    throw ArchiveError.unreadable("Truncated Deflate64 stream.")
                }
                let toRead = Int(min(remaining, 65_536))
                guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else {
                    throw ArchiveError.unreadable("Truncated Deflate64 stream.")
                }
                remaining -= UInt64(chunk.count)
                buffer = chunk
                index = 0
            }
            defer { index += 1 }
            return buffer[buffer.startIndex + index]
        }

        mutating func ensureBits(_ count: Int) throws {
            while bitCount < count {
                let next = UInt64(try readByteFromStream())
                bitBuf |= next << bitCount
                bitCount += 8
            }
        }

        private mutating func readByteFromStream() throws -> UInt8 {
            if index >= buffer.count {
                guard remaining > 0 else {
                    throw ArchiveError.unreadable("Truncated Deflate64 stream.")
                }
                let toRead = Int(min(remaining, 65_536))
                guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else {
                    throw ArchiveError.unreadable("Truncated Deflate64 stream.")
                }
                remaining -= UInt64(chunk.count)
                buffer = chunk
                index = 0
            }
            defer { index += 1 }
            return buffer[buffer.startIndex + index]
        }

        mutating func readBits(_ count: Int) throws -> Int {
            guard count > 0 else { return 0 }
            try ensureBits(count)
            let mask = (UInt64(1) << count) - 1
            let val = Int(bitBuf & mask)
            bitBuf >>= count
            bitCount -= count
            return val
        }

        mutating func alignToByte() {
            let drop = bitCount & 7
            bitBuf >>= drop
            bitCount -= drop
        }
    }

    private struct Huffman: Sendable {
        static let maxBits = 15
        let counts: [Int]
        let symbols: [Int]

        static let fixedLit: Huffman = {
            var lengths = [Int](repeating: 8, count: 288)
            for i in 144...255 { lengths[i] = 9 }
            for i in 256...279 { lengths[i] = 7 }
            return try! Huffman(lengths: lengths)
        }()

        static let fixedDist: Huffman = {
            try! Huffman(lengths: [Int](repeating: 5, count: 32))
        }()

        init(lengths: [Int]) throws {
            var counts = [Int](repeating: 0, count: Self.maxBits + 1)
            for len in lengths where len > 0 {
                guard len <= Self.maxBits else {
                    throw ArchiveError.unreadable("Invalid Huffman code length.")
                }
                counts[len] += 1
            }
            var offsets = [Int](repeating: 0, count: Self.maxBits + 1)
            var total = 0
            for bits in 1...Self.maxBits {
                offsets[bits] = total
                total += counts[bits]
            }
            var symbols = [Int](repeating: 0, count: total)
            for (sym, len) in lengths.enumerated() where len > 0 {
                symbols[offsets[len]] = sym
                offsets[len] += 1
            }
            self.counts = counts
            self.symbols = symbols
        }

        func decode(_ bits: inout BitReader) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for len in 1...Self.maxBits {
                code |= try bits.readBits(1)
                let count = counts[len]
                if code - count < first {
                    return symbols[index + (code - first)]
                }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw ArchiveError.unreadable("Invalid Huffman code in Deflate64 stream.")
        }
    }
}

extension Data {
    fileprivate func u16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    fileprivate func u32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i])
            | (UInt32(self[i + 1]) << 8)
            | (UInt32(self[i + 2]) << 16)
            | (UInt32(self[i + 3]) << 24)
    }

    fileprivate func u64(at offset: Int) -> UInt64 {
        UInt64(u32(at: offset)) | (UInt64(u32(at: offset + 4)) << 32)
    }
}
