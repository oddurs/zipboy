import Foundation
import Testing
import zlib

@testable import ZipboyKit

/// ZIPs built byte by byte, in shapes no well-behaved writer makes, so the reader and the bomb guards
/// meet what an attacker would send. Payloads are generated, not checked in: a bomb is small to describe
/// and large to unpack.
@Suite final class HostileZipTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("HostileZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // A stopped bomb still leaves up to a gigabyte behind.
    deinit { try? FileManager.default.removeItem(at: dir) }

    func folder(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func save(_ bytes: Data, as name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    /// The reason of a `suspiciousArchive` error, or nil for anything else, which a test then reports.
    func suspicion(_ work: () throws -> Void) -> String? {
        do {
            try work()
            Issue.record("Expected the archive to be stopped as suspicious")
        } catch ArchiveError.suspiciousArchive(let reason) {
            return reason
        } catch {
            Issue.record("Expected suspiciousArchive, got \(error)")
        }
        return nil
    }

    func isUnreadable(_ error: ArchiveError) -> Bool {
        if case .unreadable = error { true } else { false }
    }

    // MARK: The catalog never traps on offsets taken from the file

    @Test func catalogRefusesAZip64LocatorPointingPastTheEnd() throws {
        let zip = try save(
            CraftedZip.bytes([.init(name: "a.txt", method: 0, payload: Data("hello".utf8))], locator: .max - 15),
            as: "locator.zip")
        let error = #expect(throws: ArchiveError.self) { _ = try ZipCatalog.read(from: zip) }
        #expect(error.map(isUnreadable) == true)
    }

    @Test func catalogRefusesALocalHeaderOffsetThatOverflows() throws {
        var entry = CraftedZip.Entry(name: "a.txt", method: 0, payload: Data("hello".utf8))
        entry.centralOffset = .max - 10
        let zip = try save(CraftedZip.bytes([entry]), as: "offset.zip")
        let error = #expect(throws: ArchiveError.self) { _ = try ZipCatalog.read(from: zip) }
        #expect(error.map(isUnreadable) == true)
    }

    @Test func deflate64FallbackRefusesACompressedSizeThatOverflows() throws {
        var entry = CraftedZip.Entry(
            name: "big.bin", method: Deflate64.method, payload: Deflate64Stream.zeros(1 << 20),
            uncompressedSize: 1 << 20, crc32: zeroCRC(1 << 20))
        entry.centralCompressed = .max - 10
        let zip = try save(CraftedZip.bytes([entry]), as: "d64-size.zip")
        // libarchive refuses this entry before falling back, so drive the decoder directly.
        let out = try FileHandle(forWritingTo: try save(Data(), as: "d64-size.bin"))
        defer { try? out.close() }
        var budget: Int64?
        let error = #expect(throws: ArchiveError.self) {
            try Deflate64.extract(
                named: "big.bin", occurrence: 0, from: zip, encoding: .auto, to: out, budget: &budget,
                capacity: { nil }, report: {},
                admit: { _, _ in })
        }
        #expect(error.map(isUnreadable) == true)
    }

    @Test func deflate64FallbackRefusesADirectoryThatOverflows() throws {
        let entry = CraftedZip.Entry(
            name: "big.bin", method: Deflate64.method, payload: Deflate64Stream.zeros(1 << 20),
            uncompressedSize: 1 << 20, crc32: zeroCRC(1 << 20))
        let zip = try save(CraftedZip.bytes([entry], zip64Directory: (offset: .max - 10, size: 100)), as: "d64-cd.zip")
        let out = try FileHandle(forWritingTo: try save(Data(), as: "d64-cd.bin"))
        defer { try? out.close() }
        var budget: Int64?
        let error = #expect(throws: ArchiveError.self) {
            try Deflate64.extract(
                named: "big.bin", occurrence: 0, from: zip, encoding: .auto, to: out, budget: &budget,
                capacity: { nil }, report: {},
                admit: { _, _ in })
        }
        #expect(error.map(isUnreadable) == true)
    }

    // MARK: The bomb guard tells bombs from files that compress well

    @Test func extractsAHundredMebibytesOfZeros() throws {
        // A blank disk image: Deflate's best on zeros is about 1,030:1.
        let size: UInt64 = 100 << 20
        let entry = CraftedZip.Entry(
            name: "disk.img", method: 8, payload: DeflatedZeros.stream(mebibytes: 100), uncompressedSize: size,
            crc32: zeroCRC(size))
        let zip = try save(CraftedZip.bytes([entry]), as: "zeros.zip")
        let out = try folder("zeros")
        _ = try Archive.extract(zip, into: out)
        let attributes = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("disk.img").path)
        #expect(attributes[.size] as? UInt64 == size)
    }

    @Test func refusesATenGigabyteSingleEntryBombBeforeWritingAnything() throws {
        let size: UInt64 = 10 << 30
        let entry = CraftedZip.Entry(
            name: "bomb.bin", method: 8, payload: DeflatedZeros.stream(mebibytes: 10 << 10), uncompressedSize: size)
        let zip = try save(CraftedZip.bytes([entry]), as: "ten-gigabytes.zip")
        let out = try folder("ten-gigabytes")
        let reason = suspicion { _ = try Archive.extract(zip, into: out, capacity: { 1 << 40 }) }
        #expect(reason?.contains("bomb.bin") == true)
        #expect(try Archive.contents(of: out).isEmpty)
    }

    @Test func stopsAManyEntryBombBeforeAGigabyte() throws {
        // The innermost layer of 42.zip: sixteen entries, each harmless beside the archive's size alone.
        let entries = (0..<16).map { index in
            CraftedZip.Entry(
                name: "\(index).bin", method: 8, payload: DeflatedZeros.stream(mebibytes: 256),
                uncompressedSize: 256 << 20, crc32: zeroCRC(256 << 20))
        }
        let zip = try save(CraftedZip.bytes(entries), as: "sixteen.zip")
        let out = try folder("sixteen")
        // A disk with 1.5 GB free: free space alone would let more than a gigabyte through first.
        let capacity = { 1_500_000_000 - Int64((try? Archive.written(in: out)) ?? 0) }
        // Stopped up front at the fourth entry, the first to take the total past the floor.
        let reason = suspicion { _ = try Archive.extract(zip, into: out, capacity: capacity) }
        #expect(reason?.contains("“3.bin” would expand") == true)
        #expect(try Archive.written(in: out) <= 1_000_000_000)
    }

    @Test func stopsABombHiddenBehindPaddingWhileStreaming() throws {
        // Incompressible padding after the bomb makes the whole file large enough that its declared size
        // looks plausible; only the bytes read so far give it away.
        let bomb = CraftedZip.Entry(
            name: "bomb.bin", method: 8, payload: DeflatedZeros.stream(mebibytes: 2 << 10), uncompressedSize: 2 << 30,
            crc32: zeroCRC(2 << 30))
        let zip = try save(CraftedZip.bytes([bomb, CraftedZip.Entry.padding(megabytes: 25)]), as: "padded.zip")
        let out = try folder("padded")
        let reason = suspicion { _ = try Archive.extract(zip, into: out, capacity: { 1 << 40 }) }
        #expect(reason?.contains("expanded past") == true)
        #expect(try Archive.written(in: out) <= 1_000_000_000)
    }

    @Test func stopsATarHardlinkBombAtTheExpansionGuard() throws {
        let source = try folder("hardlink-bomb-src")
        let seed = source.appendingPathComponent("seed.bin")
        try Data(count: 64 << 20).write(to: seed)
        var members = ["seed.bin"]
        for index in 0..<100 {
            let name = String(format: "link-%03d.bin", index)
            try FileManager.default.linkItem(at: seed, to: source.appendingPathComponent(name))
            members.append(name)
        }
        let tar = dir.appendingPathComponent("hardlink-bomb.tar")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["-cf", tar.path, "-C", source.path] + members
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let out = try folder("hardlink-bomb-out")
        let reason = suspicion { _ = try Archive.extract(tar, into: out, capacity: { 1 << 40 }) }
        #expect(reason?.contains("decompression bomb") == true)
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("link-099.bin").path))
    }

    // MARK: The Deflate64 fallback streams under the same guards

    @Test func stopsADeflate64EntryThatExpandsPastItsDeclaredSize() throws {
        let entry = CraftedZip.Entry(
            name: "big.bin", method: Deflate64.method, payload: Deflate64Stream.zeros(8 << 20),
            uncompressedSize: 1 << 20)
        let zip = try save(CraftedZip.bytes([entry]), as: "d64-liar.zip")
        let out = try folder("d64-liar")
        let reason = suspicion { _ = try Archive.extract(zip, into: out, capacity: { 1 << 40 }) }
        #expect(reason?.contains("declared size") == true)
    }

    @Test func deflate64AsksTheBombGuardBeforeWritingEachWindow() throws {
        // The real limits need a gigabyte of output, which this decoder takes minutes to make in a debug
        // build, so stand in for the guard with one that stops at a mebibyte.
        let size: UInt64 = 8 << 20
        let entry = CraftedZip.Entry(
            name: "big.bin", method: Deflate64.method, payload: Deflate64Stream.zeros(size), uncompressedSize: size,
            crc32: zeroCRC(size))
        let zip = try save(CraftedZip.bytes([entry]), as: "d64-guarded.zip")
        let file = try save(Data(), as: "d64-guarded.bin")
        let out = try FileHandle(forWritingTo: file)
        defer { try? out.close() }
        var budget: Int64?
        var admitted: Int64 = 0
        var consumed: [UInt64] = []
        let reason = suspicion {
            try Deflate64.extract(
                named: "big.bin", occurrence: 0, from: zip, encoding: .auto, to: out, budget: &budget,
                capacity: { nil }, report: {},
                admit: { bytes, read in
                    consumed.append(read)
                    guard admitted + bytes <= 1 << 20 else { throw ArchiveError.suspiciousArchive("stopped") }
                    admitted += bytes
                })
        }
        #expect(reason == "stopped")
        try out.synchronize()
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 == admitted)
        #expect(consumed == consumed.sorted() && consumed.allSatisfy { $0 > 0 && $0 <= entry.payload.count })
    }
}

extension Archive {
    /// The bytes of every regular file left under `root`.
    fileprivate static func written(in root: URL) throws -> UInt64 {
        try contents(of: root).reduce(0) { total, path in
            let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)
            return total
                + ((attributes[.type] as? FileAttributeType) == .typeRegular ? attributes[.size] as? UInt64 ?? 0 : 0)
        }
    }
}

/// The CRC-32 of `length` zero bytes, built by doubling so a test never hashes gigabytes.
private func zeroCRC(_ length: UInt64) -> UInt32 {
    let block = [UInt8](repeating: 0, count: 1 << 20)
    var crc: uLong = 0
    var remaining = length
    let whole = block.withUnsafeBufferPointer { zlib.crc32(0, $0.baseAddress, uInt($0.count)) }
    while remaining >= UInt64(block.count) {
        crc = crc32_combine(crc, whole, Int(block.count))
        remaining -= UInt64(block.count)
    }
    let tail = block.withUnsafeBufferPointer { zlib.crc32(0, $0.baseAddress, uInt(remaining)) }
    return UInt32(crc32_combine(crc, tail, Int(remaining)))
}

/// A raw Deflate stream of zeros. Each mebibyte is compressed alone and fully flushed, so it ends
/// byte-aligned and refers to nothing before it: one compressed block, repeated, is a valid stream.
private enum DeflatedZeros {
    static func stream(mebibytes: Int) -> Data {
        var stream = z_stream()
        deflateInit2_(
            &stream, 9, Z_DEFLATED, -15, 9, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var input = [UInt8](repeating: 0, count: 1 << 20)
        var output = [UInt8](repeating: 0, count: 1 << 16)
        var block = Data()
        input.withUnsafeMutableBufferPointer { inPtr in
            stream.next_in = inPtr.baseAddress
            stream.avail_in = uInt(inPtr.count)
            repeat {
                output.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = uInt(outPtr.count)
                    deflate(&stream, Z_FULL_FLUSH)
                    block.append(outPtr.baseAddress!, count: outPtr.count - Int(stream.avail_out))
                }
            } while stream.avail_out == 0
        }
        var data = Data(capacity: block.count * mebibytes + 2)
        for _ in 0..<mebibytes { data.append(block) }
        // An empty final block with fixed codes.
        data.append(contentsOf: [0x03, 0x00])
        return data
    }
}

/// A Deflate64 stream of zeros written by hand, since nothing on a stock Mac writes Deflate64: one
/// fixed-code block of a literal zero followed by the longest matches Deflate64 allows, 65,538 bytes
/// at distance 1 (length code 285 with 16 extra bits).
private enum Deflate64Stream {
    static func zeros(_ count: UInt64) -> Data {
        var bits = BitWriter()
        bits.write(1, count: 1)
        bits.write(1, count: 2)
        bits.code(0x30, length: 8)
        var remaining = count - 1
        while remaining >= 3 {
            let length = min(remaining, 65_538)
            bits.code(0xC5, length: 8)
            bits.write(Int(length - 3), count: 16)
            bits.code(0, length: 5)
            remaining -= length
        }
        for _ in 0..<remaining { bits.code(0x30, length: 8) }
        bits.code(0, length: 7)
        return bits.finish()
    }

    struct BitWriter {
        var data = Data()
        var buffer = 0
        var used = 0

        /// Writes `value`'s low `count` bits, least significant first, as Deflate stores extra bits.
        mutating func write(_ value: Int, count: Int) {
            for bit in 0..<count {
                buffer |= ((value >> bit) & 1) << used
                used += 1
                if used == 8 {
                    data.append(UInt8(buffer))
                    buffer = 0
                    used = 0
                }
            }
        }

        /// Writes a Huffman code, which Deflate stores most significant bit first.
        mutating func code(_ code: Int, length: Int) {
            for bit in stride(from: length - 1, through: 0, by: -1) { write((code >> bit) & 1, count: 1) }
        }

        mutating func finish() -> Data {
            if used > 0 { data.append(UInt8(buffer)) }
            return data
        }
    }
}

/// Writes a ZIP from entries whose sizes, offsets and payloads are taken as given, never checked.
private enum CraftedZip {
    struct Entry {
        var name: String
        var method: UInt16
        var payload: Data
        var uncompressedSize: UInt64
        var crc32: UInt32
        /// The local header offset the Central Directory claims, in place of the real one.
        var centralOffset: UInt64?
        /// The compressed size the Central Directory claims, in place of the real one.
        var centralCompressed: UInt64?

        init(name: String, method: UInt16, payload: Data, uncompressedSize: UInt64? = nil, crc32: UInt32? = nil) {
            self.name = name
            self.method = method
            self.payload = payload
            self.uncompressedSize = uncompressedSize ?? UInt64(payload.count)
            self.crc32 = crc32 ?? UInt32(payload.withUnsafeBytes { zlib.crc32(0, $0.baseAddress, uInt($0.count)) })
        }

        /// A stored entry of zeros, which grows the archive without compressing.
        static func padding(megabytes: Int) -> Entry {
            let size = UInt64(megabytes * 1_000_000)
            return Entry(name: "padding.bin", method: 0, payload: Data(count: Int(size)), crc32: zeroCRC(size))
        }
    }

    static let wide: UInt64 = 0xFFFF_FFFF

    /// `locator` writes a Zip64 locator pointing at that offset; `zip64Directory` writes a Zip64 end
    /// record claiming that directory, with a locator pointing at the record.
    static func bytes(
        _ entries: [Entry], locator: UInt64? = nil, zip64Directory: (offset: UInt64, size: UInt64)? = nil
    ) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt64(out.count)
            let compressed = UInt64(entry.payload.count)
            let zip64 = entry.uncompressedSize >= wide || compressed >= wide
            let name = Data(entry.name.utf8)

            var localExtra = Data()
            if zip64 {
                localExtra.le(UInt16(1), UInt16(16))
                localExtra.le(entry.uncompressedSize, compressed)
            }
            out.le(UInt32(0x0403_4b50), UInt16(zip64 ? 45 : 20), UInt16(0), entry.method, UInt16(0), UInt16(0x21))
            out.le(entry.crc32, UInt32(min(compressed, wide)), UInt32(min(entry.uncompressedSize, wide)))
            out.le(UInt16(name.count), UInt16(localExtra.count))
            out.append(name)
            out.append(localExtra)
            out.append(entry.payload)

            let claimedOffset = entry.centralOffset ?? offset
            let claimedCompressed = entry.centralCompressed ?? compressed
            var fields = Data()
            if entry.uncompressedSize >= wide { fields.le(entry.uncompressedSize) }
            if claimedCompressed >= wide { fields.le(claimedCompressed) }
            if claimedOffset >= wide { fields.le(claimedOffset) }
            var centralExtra = Data()
            if !fields.isEmpty {
                centralExtra.le(UInt16(1), UInt16(fields.count))
                centralExtra.append(fields)
            }
            central.le(UInt32(0x0201_4b50), UInt16(0x031E), UInt16(zip64 ? 45 : 20), UInt16(0), entry.method)
            central.le(UInt16(0), UInt16(0x21), entry.crc32)
            central.le(UInt32(min(claimedCompressed, wide)), UInt32(min(entry.uncompressedSize, wide)))
            central.le(UInt16(name.count), UInt16(centralExtra.count), UInt16(0), UInt16(0), UInt16(0))
            central.le(UInt32(0o100644) << 16, UInt32(min(claimedOffset, wide)))
            central.append(name)
            central.append(centralExtra)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        if let zip64Directory {
            let record = UInt64(out.count)
            out.le(UInt32(0x0606_4b50), UInt64(44), UInt16(45), UInt16(45), UInt32(0), UInt32(0))
            out.le(UInt64(entries.count), UInt64(entries.count), zip64Directory.size, zip64Directory.offset)
            out.le(UInt32(0x0706_4b50), UInt32(0), record, UInt32(1))
        }
        if let locator {
            out.le(UInt32(0x0706_4b50), UInt32(0), locator, UInt32(1))
        }
        out.le(UInt32(0x0605_4b50), UInt16(0), UInt16(0), UInt16(entries.count), UInt16(entries.count))
        out.le(UInt32(central.count), centralOffset, UInt16(0))
        return out
    }
}

extension Data {
    fileprivate mutating func le<each T: FixedWidthInteger>(_ values: repeat each T) {
        repeat append(contentsOf: Swift.withUnsafeBytes(of: (each values).littleEndian, Array.init))
    }
}
