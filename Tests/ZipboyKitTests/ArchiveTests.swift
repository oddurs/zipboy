import Foundation
import Testing
import zlib

@testable import ZipboyKit

/// Round trips through real files, since the point is what libarchive and other tools make of them.
@Suite struct ArchiveTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func folder(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ path: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Runs a system tool and returns what it printed.
    func run(_ tool: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func roundTripsFilesFoldersAndNames() throws {
        let source = try folder("source")
        try write("hello", to: "a.txt", in: source)
        try write("deep", to: "nested/deeper/b.md", in: source)
        try write("ü", to: "Ünïcödé.txt", in: source)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("link").path, withDestinationPath: "a.txt")

        let zip = dir.appendingPathComponent("out.zip")
        try Archive.writeZip(from: source, to: zip)
        let back = try folder("back")
        let summary = try Archive.extract(zip, into: back)

        #expect(summary.format.hasPrefix("ZIP"))
        #expect(!summary.encrypted)
        #expect(try read("a.txt", in: back) == "hello")
        #expect(try read("nested/deeper/b.md", in: back) == "deep")
        #expect(try read("Ünïcödé.txt", in: back) == "ü")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: back.appendingPathComponent("link").path)
                == "a.txt")
        #expect(try Archive.contents(of: back) == Archive.contents(of: source))
    }

    @Test func writesZipsOtherToolsRead() throws {
        let source = try folder("source")
        try write("hello", to: "Ünïcödé/a.txt", in: source)
        let zip = dir.appendingPathComponent("out.zip")
        try Archive.writeZip(from: source, to: zip)

        // Composed form, as Windows and Linux expect, whatever form APFS stored. Checked in the bytes,
        // since unzip prints every non-ASCII byte as "?".
        let bytes = try Data(contentsOf: zip)
        let name = "Ünïcödé/a.txt"
        #expect(bytes.range(of: Data(name.precomposedStringWithCanonicalMapping.utf8)) != nil)
        #expect(bytes.range(of: Data(name.decomposedStringWithCanonicalMapping.utf8)) == nil)
        let (testStatus, _) = try run("/usr/bin/unzip", ["-t", zip.path])
        #expect(testStatus == 0)
    }

    @Test func leavesOutFinderMetadata() throws {
        let source = try folder("source")
        try write("x", to: "a.txt", in: source)
        try write("x", to: ".DS_Store", in: source)
        try write("x", to: "__MACOSX/._a.txt", in: source)
        let zip = dir.appendingPathComponent("out.zip")
        try Archive.writeZip(from: source, to: zip)
        let back = try folder("back")
        _ = try Archive.extract(zip, into: back)
        #expect(try Archive.contents(of: back) == ["a.txt"])
    }

    @Test func encryptsAndAsksForThePassword() throws {
        let source = try folder("source")
        try write("secret", to: "a.txt", in: source)
        let zip = dir.appendingPathComponent("locked.zip")
        try Archive.writeZip(from: source, to: zip, password: "hunter2")

        #expect(throws: ArchiveError.passwordRequired) { try Archive.extract(zip, into: try folder("none")) }
        #expect(throws: ArchiveError.wrongPassword) {
            try Archive.extract(zip, into: try folder("wrong"), password: "nope")
        }
        let back = try folder("back")
        let summary = try Archive.extract(zip, into: back, password: "hunter2")
        #expect(summary.encrypted)
        #expect(try read("a.txt", in: back) == "secret")
    }

    @Test func refusesEntriesThatClimbOut() throws {
        // bsdtar keeps the names as given with -P, which is how a hostile archive is built.
        let source = try folder("evil/inner")
        try write("x", to: "ok.txt", in: source)
        let tar = dir.appendingPathComponent("evil.tar")
        let (status, out) = try run(
            "/usr/bin/bsdtar", ["-cPf", tar.path, "-s", ",^.*inner/ok.txt$,../escaped.txt,", source.path + "/ok.txt"])
        #expect(status == 0, "\(out)")

        let root = try folder("root")
        let summary = try Archive.extract(tar, into: root)
        #expect(summary.skipped == ["../escaped.txt"])
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escaped.txt").path))
    }

    @Test func refusesToWriteThroughALink() throws {
        let source = try folder("source")
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("up").path, withDestinationPath: ".")
        try write("x", to: "a.txt", in: source)
        let tar = dir.appendingPathComponent("stacked.tar")
        // `up` alone stays inside, but a file written through it must not be trusted.
        let (status, out) = try run(
            "/usr/bin/bsdtar", ["-cf", tar.path, "-C", source.path, "-s", ",^a.txt$,up/a.txt,", "up", "a.txt"])
        #expect(status == 0, "\(out)")

        let root = try folder("root")
        let summary = try Archive.extract(tar, into: root)
        #expect(summary.skipped == ["up/a.txt"])
    }

    @Test func readsRarAnd7z() throws {
        let rar = try #require(
            Bundle.module.url(forResource: "container", withExtension: "rar", subdirectory: "Fixtures"))
        let rarRoot = try folder("rar")
        let rarSummary = try Archive.extract(rar, into: rarRoot)
        #expect(rarSummary.format.hasPrefix("RAR"))
        #expect(try Archive.contents(of: rarRoot) == ["container"])

        let source = try folder("source")
        try write("seven", to: "s/7.txt", in: source)
        let sevenZip = dir.appendingPathComponent("t.7z")
        let (status, out) = try run(
            "/usr/bin/bsdtar", ["--format", "7zip", "-cf", sevenZip.path, "-C", source.path, "s"])
        #expect(status == 0, "\(out)")
        let sevenRoot = try folder("7z")
        _ = try Archive.extract(sevenZip, into: sevenRoot)
        #expect(try read("s/7.txt", in: sevenRoot) == "seven")
    }

    @Test func reportsProgressAndStopsWhenAsked() throws {
        let source = try folder("source")
        try Data(repeating: 7, count: 3 << 20).write(to: source.appendingPathComponent("a.bin"))
        try Data(repeating: 9, count: 3 << 20).write(to: source.appendingPathComponent("b.bin"))
        let zip = dir.appendingPathComponent("out.zip")
        try Archive.writeZip(from: source, to: zip)

        var seen: [Double] = []
        _ = try Archive.extract(zip, into: try folder("all")) { done in
            seen.append(done)
            return true
        }
        #expect(!seen.isEmpty)
        #expect(seen == seen.sorted())
        #expect(seen.allSatisfy { (0...1).contains($0) })

        #expect(throws: ArchiveError.cancelled) {
            try Archive.extract(zip, into: try folder("stopped")) { _ in false }
        }

        var wrote: [Double] = []
        try Archive.writeZip(from: source, to: dir.appendingPathComponent("again.zip")) { done in
            wrote.append(done)
            return true
        }
        #expect(wrote.last == 1)
        #expect(wrote == wrote.sorted())
        #expect(throws: ArchiveError.cancelled) {
            try Archive.writeZip(from: source, to: dir.appendingPathComponent("stopped.zip")) { _ in false }
        }
    }

    @Test func stopsBeforeFillingTheDisk() throws {
        let source = try folder("source")
        try write("small", to: "a.txt", in: source)
        try Data(repeating: 1, count: 3 << 20).write(to: source.appendingPathComponent("big.bin"))
        let zip = dir.appendingPathComponent("out.zip")
        try Archive.writeZip(from: source, to: zip)

        let root = try folder("root")
        // A volume with 1 MB free, less the reserve, can't take a 3 MB file.
        #expect(throws: ArchiveError.noSpace(needed: 3 << 20, available: 1 << 20)) {
            try Archive.extract(zip, into: root, capacity: { 1 << 20 })
        }
        // Nothing half-written is left for the big file.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("big.bin").path))
        #expect(ArchiveError.noSpace(needed: 3 << 20, available: 1 << 20).errorDescription?.contains("3.1 MB") == true)
    }

    @Test func refusesAGzippedFileThatIsNotAnArchive() throws {
        // A line of text, as from `echo hello`; mtree reads each line as an entry.
        try write("hello\n", to: "hello.txt", in: dir)
        let gz = dir.appendingPathComponent("hello.gz")
        let (status, out) = try run("/bin/sh", ["-c", "gzip -c '\(dir.path)/hello.txt' > '\(gz.path)'"])
        #expect(status == 0, "\(out)")
        // mtree, a text format for describing file trees, used to claim this as a one-entry archive.
        #expect(throws: ArchiveError.self) { try Archive.extract(gz, into: try folder("gz")) }
    }

    /// libarchive can't decrypt 7z or RAR. Asking for a password would loop forever, since every answer
    /// fails; the error must say the archive can't be opened at all.
    @Test(arguments: ["encrypted.7z", "encrypted-data.rar", "encrypted-header.rar"])
    func saysWhenEncryptionIsUnsupported(_ name: String) throws {
        let (base, ext) = ((name as NSString).deletingPathExtension, (name as NSString).pathExtension)
        let url = try #require(Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"))
        for password in [nil, "secret"] as [String?] {
            do {
                _ = try Archive.extract(url, into: try folder("\(name)-\(password ?? "none")"), password: password)
                Issue.record("\(name) opened without being decrypted")
            } catch let error as ArchiveError {
                #expect(error != .passwordRequired && error != .wrongPassword, "\(name): \(error)")
                #expect(error.errorDescription?.contains("encrypted") == true, "\(name): \(error)")
            }
        }
    }

    /// A ZIP whose one entry is named by `raw`, with the UTF-8 flag clear, as old Windows tools write.
    func zip(namedBy raw: [UInt8]) throws -> URL {
        let placeholder = String(repeating: "X", count: raw.count)
        let source = try folder("named-\(UUID().uuidString)")
        try write("x", to: placeholder, in: source)
        let zip = dir.appendingPathComponent("\(UUID().uuidString).zip")
        try Archive.writeZip(from: source, to: zip)
        // An ASCII name is written without the UTF-8 flag; swap in the raw bytes in both headers.
        var bytes = try Data(contentsOf: zip)
        var at = bytes.startIndex
        while let range = bytes.range(of: Data(placeholder.utf8), in: at..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: raw)
            at = range.upperBound
        }
        try bytes.write(to: zip)
        return zip
    }

    @Test func readsCodePage437NamesFromOldZips() throws {
        // "über.txt" in code page 437, where ü is 0x81.
        let zip = try zip(namedBy: [0x81] + Array("ber.txt".utf8))
        let root = try folder("cp437")
        _ = try Archive.extract(zip, into: root)
        #expect(try Archive.contents(of: root) == ["über.txt"])
    }

    @Test func readsUnflaggedUTF8NamesAsUTF8() throws {
        // macOS's own tools write UTF-8 names without setting the flag.
        let zip = try zip(namedBy: Array("über.txt".utf8))
        let root = try folder("utf8")
        _ = try Archive.extract(zip, into: root)
        #expect(try Archive.contents(of: root).map { $0.precomposedStringWithCanonicalMapping } == ["über.txt"])
    }

    @Test func reportsGarbage() throws {
        let junk = dir.appendingPathComponent("junk.zip")
        try Data("not an archive".utf8).write(to: junk)
        #expect(throws: ArchiveError.self) { try Archive.extract(junk, into: try folder("x")) }
    }

    @Test func preservesHardlinksAndSkipsUnsafeOnes() throws {
        let source = try folder("hardlinks")
        try write("shared payload", to: "a.txt", in: source)
        try FileManager.default.linkItem(
            at: source.appendingPathComponent("a.txt"),
            to: source.appendingPathComponent("b.txt"))
        let tar = dir.appendingPathComponent("hardlinks.tar")
        let (status, out) = try run("/usr/bin/bsdtar", ["-cf", tar.path, "-C", source.path, "a.txt", "b.txt"])
        #expect(status == 0, "\(out)")

        let root = try folder("hardlinks-out")
        let summary = try Archive.extract(tar, into: root)
        #expect(summary.skipped.isEmpty)
        #expect(try read("a.txt", in: root) == "shared payload")
        #expect(try read("b.txt", in: root) == "shared payload")
    }

    @Test func stopsWhenAnEntryExceedsCapacityMidStream() throws {
        let source = try folder("stream-source")
        let fullSize = UInt32(3 << 20)
        try Data(repeating: 0x41, count: Int(fullSize)).write(to: source.appendingPathComponent("streamed.bin"))
        let zip = dir.appendingPathComponent("streamed.zip")
        try Archive.writeZip(from: source, to: zip)

        // Patch the declared uncompressed size (3 MB -> 64 bytes) in the ZIP headers so the up-front
        // size check passes and only the mid-stream chunk check can stop it from filling the disk.
        var bytes = try Data(contentsOf: zip)
        let target = withUnsafeBytes(of: fullSize.littleEndian) { Data($0) }
        let spoofed = withUnsafeBytes(of: UInt32(64).littleEndian) { Data($0) }
        var at = bytes.startIndex
        while let range = bytes.range(of: target, in: at..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: spoofed)
            at = range.upperBound
        }
        try bytes.write(to: zip)

        let root = try folder("stream-out")
        #expect(throws: ArchiveError.self) {
            try Archive.extract(zip, into: root, capacity: { 1 << 20 })
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("streamed.bin").path))
    }

    @Test func cancelledWriteLeavesExistingArchiveIntact() throws {
        let initial = try folder("initial")
        try write("keep me", to: "kept.txt", in: initial)
        let zip = dir.appendingPathComponent("durable.zip")
        try Archive.writeZip(from: initial, to: zip)
        let originalBytes = try Data(contentsOf: zip)

        let replacement = try folder("replacement")
        try Data(repeating: 0x5A, count: 2 << 20).write(to: replacement.appendingPathComponent("big.bin"))
        #expect(throws: ArchiveError.cancelled) {
            try Archive.writeZip(from: replacement, to: zip) { _ in false }
        }
        #expect(try Data(contentsOf: zip) == originalBytes)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter {
            $0.hasPrefix(".Zipboy-")
        }
        #expect(leftovers.isEmpty)
    }

    @Test func writeZipHonorsCompressionLevel() throws {
        let source = try folder("levels")
        // Pseudo-random text with repeated phrases so higher Deflate effort finds longer matches.
        var text = ""
        for i in 0..<4000 {
            text += "Zipboy archive entry line \(i % 97) with compressible content block \((i * 31) % 113).\n"
        }
        try write(text, to: "log.txt", in: source)

        let fastZip = dir.appendingPathComponent("fast.zip")
        let balancedZip = dir.appendingPathComponent("balanced.zip")
        let bestZip = dir.appendingPathComponent("best.zip")

        try Archive.writeZip(from: source, to: fastZip, compressionLevel: .fast)
        try Archive.writeZip(from: source, to: balancedZip, compressionLevel: .balanced)
        try Archive.writeZip(from: source, to: bestZip, compressionLevel: .best)

        let fastSize = try Data(contentsOf: fastZip).count
        let bestSize = try Data(contentsOf: bestZip).count
        #expect(bestSize <= fastSize)

        for zip in [fastZip, balancedZip, bestZip] {
            let out = try folder("verify-\(zip.lastPathComponent)")
            _ = try Archive.extract(zip, into: out)
            #expect(try read("log.txt", in: out) == text)
        }
    }

    @Test func catalogParsesStandardAndMatrixZipsAndMatchesTree() throws {
        let source = try folder("cat-src")
        try write("alpha", to: "a.txt", in: source)
        try write("beta-content", to: "nested/deeper/b.txt", in: source)
        try write("ünicode", to: "Ünïcödé/カフェ.txt", in: source)
        let zip = dir.appendingPathComponent("catalog.zip")
        try Archive.writeZip(from: source, to: zip)

        let catalog = try ZipCatalog.read(from: zip)
        #expect(!catalog.isEncrypted)
        let paths = Set(catalog.entries.filter { !$0.isDirectory }.map(\.path))
        #expect(paths == ["a.txt", "nested/deeper/b.txt", "Ünïcödé/カフェ.txt"])

        let aEntry = try #require(catalog.entries.first { $0.path == "a.txt" })
        #expect(aEntry.uncompressedSize == 5)
        let alphaFile = dir.appendingPathComponent("alpha-check.txt")
        try Data("alpha".utf8).write(to: alphaFile)
        #expect(aEntry.crc32 == (try Checksums.compute(for: alphaFile).crc32))

        for name in ["zip-deflate", "zip-store", "zip-zip64", "zip-data-descriptor", "zip-aes256", "zip-zipcrypto"] {
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "zip", subdirectory: "Fixtures/matrix"))
            let parsed = try ZipCatalog.read(from: url)
            #expect(!parsed.entries.isEmpty, "\(name).zip")
            if name.contains("aes") || name.contains("zipcrypto") {
                #expect(parsed.isEncrypted)
            }
        }

        // Truncated or corrupt files must be rejected by ZipCatalog.
        let truncated = dir.appendingPathComponent("truncated.zip")
        let fullBytes = try Data(contentsOf: zip)
        try fullBytes.prefix(fullBytes.count - 10).write(to: truncated)
        #expect(throws: ArchiveError.self) {
            _ = try ZipCatalog.read(from: truncated)
        }
    }

    @Test func zipWriterCopiesUnchangedEntriesByteForByteAndUpdatesEditedOnes() throws {
        let source = try folder("writer-src")
        let payloadA = Data((0..<16384).map { UInt8(($0 * 37) & 0xff) })
        let payloadB = Data("unchanged-renamed-file-payload-1234567890".utf8)
        try payloadA.write(to: source.appendingPathComponent("keep.bin"))
        try payloadB.write(to: source.appendingPathComponent("oldname.txt"))
        try write("will-be-replaced", to: "edit.txt", in: source)

        let originalZip = dir.appendingPathComponent("original.zip")
        try Archive.writeZip(from: source, to: originalZip, compressionLevel: .best)

        let catalog = try ZipCatalog.read(from: originalZip)
        let keepEntry = try #require(catalog.entries.first { $0.path == "keep.bin" })
        let renameEntry = try #require(catalog.entries.first { $0.path == "oldname.txt" })

        let originalFile = try FileHandle(forReadingFrom: originalZip)
        let origRange = try ZipCatalog.payloadRange(in: originalFile, for: keepEntry)
        try originalFile.seek(toOffset: origRange.offset)
        let originalCompressedKeep = try #require(
            try originalFile.read(upToCount: Int(origRange.length)))
        try originalFile.close()

        let workspace = try folder("writer-ws")
        try write("brand-new-content", to: "edit.txt", in: workspace)
        try write("added-later", to: "folder/added.txt", in: workspace)

        let updatedZip = dir.appendingPathComponent("updated.zip")
        try ZipWriter.write(
            items: [
                .verbatim(keepEntry, newPath: nil),
                .verbatim(renameEntry, newPath: "sub/newname.txt"),
                .workspace(url: workspace.appendingPathComponent("edit.txt"), path: "edit.txt"),
                .workspace(url: workspace.appendingPathComponent("folder/added.txt"), path: "folder/added.txt"),
            ],
            sourceZip: originalZip,
            to: updatedZip,
            compressionLevel: .balanced
        )

        let (testStatus, out) = try run("/usr/bin/unzip", ["-t", updatedZip.path])
        #expect(testStatus == 0, "\(out)")

        let updatedCatalog = try ZipCatalog.read(from: updatedZip)
        let updatedKeep = try #require(updatedCatalog.entries.first { $0.path == "keep.bin" })
        #expect(updatedKeep.crc32 == keepEntry.crc32)
        #expect(updatedKeep.compressedSize == keepEntry.compressedSize)

        let updatedFile = try FileHandle(forReadingFrom: updatedZip)
        let updRange = try ZipCatalog.payloadRange(in: updatedFile, for: updatedKeep)
        try updatedFile.seek(toOffset: updRange.offset)
        let updatedCompressedKeep = try #require(
            try updatedFile.read(upToCount: Int(updRange.length)))
        try updatedFile.close()
        #expect(updatedCompressedKeep == originalCompressedKeep)

        let extracted = try folder("writer-extracted")
        _ = try Archive.extract(updatedZip, into: extracted)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("keep.bin")) == payloadA)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("sub/newname.txt")) == payloadB)
        #expect(try read("edit.txt", in: extracted) == "brand-new-content")
        #expect(try read("folder/added.txt", in: extracted) == "added-later")
    }

    /// One stored entry whose raw name is `ete.txt` while its 0x7075 Unicode Path field names it
    /// `été.txt`, with an extended timestamp and a uid/gid field beside it, as Info-ZIP writes them.
    func unicodePathZip() throws -> (url: URL, timestamp: Data, owner: Data) {
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
        func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8(v >> ($0 * 8) & 0xff) }) }
        func crc32(_ data: Data) -> UInt32 {
            UInt32(data.withUnsafeBytes { zlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) })
        }
        let raw = Data("ete.txt".utf8)
        let unicode = Data("été.txt".utf8)
        let body = Data("data".utf8)
        let timestamp = le16(0x5455) + le16(5) + Data([0x01]) + le32(1_700_000_000)
        let owner = le16(0x7875) + le16(11) + Data([1, 4]) + le32(501) + Data([4]) + le32(20)
        let unicodePath = le16(0x7075) + le16(5 + unicode.count) + Data([1]) + le32(crc32(raw)) + unicode
        let extra = unicodePath + timestamp + owner
        let crc = crc32(body)

        var local = le32(0x0403_4b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21)
        local += le32(crc) + le32(UInt32(body.count)) + le32(UInt32(body.count))
        local += le16(raw.count) + le16(extra.count) + raw + extra + body
        var central = le32(0x0201_4b50) + le16(0x031E) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21)
        central += le32(crc) + le32(UInt32(body.count)) + le32(UInt32(body.count))
        central += le16(raw.count) + le16(extra.count) + le16(0) + le16(0) + le16(0) + le32(0o100644 << 16) + le32(0)
        central += raw + extra
        let end =
            le32(0x0605_4b50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(UInt32(central.count))
            + le32(UInt32(local.count)) + le16(0)

        let url = dir.appendingPathComponent("unicode-path.zip")
        try (local + central + end).write(to: url)
        return (url, timestamp, owner)
    }

    /// The extra field of the local header at the start of `zip`.
    func firstLocalExtra(in zip: URL) throws -> Data {
        let bytes = try Data(contentsOf: zip)
        let nameLength = Int(bytes[26]) | Int(bytes[27]) << 8
        let extraLength = Int(bytes[28]) | Int(bytes[29]) << 8
        return bytes.subdata(in: (30 + nameLength)..<(30 + nameLength + extraLength))
    }

    @Test func deltaSavesKeepExtraFields() throws {
        let (source, timestamp, owner) = try unicodePathZip()
        let entry = try #require(try ZipCatalog.read(from: source).entries.first)
        #expect(entry.path == "été.txt")

        let copied = dir.appendingPathComponent("copied.zip")
        try ZipWriter.write(items: [.verbatim(entry)], sourceZip: source, to: copied)
        let copy = try #require(try ZipCatalog.read(from: copied).entries.first)
        #expect(copy.path == "été.txt")
        #expect(copy.extraField == entry.extraField)

        // The 0x7075 field names the old path, and would override the new one in readers that honour it.
        let renamed = dir.appendingPathComponent("renamed.zip")
        try ZipWriter.write(items: [.verbatim(entry, newPath: "après.txt")], sourceZip: source, to: renamed)
        let moved = try #require(try ZipCatalog.read(from: renamed).entries.first)
        #expect(moved.path == "après.txt")
        #expect(moved.extraField == timestamp + owner)
        #expect(try firstLocalExtra(in: renamed) == timestamp + owner)

        let (status, out) = try run("/usr/bin/unzip", ["-t", renamed.path])
        #expect(status == 0, "\(out)")
    }

    @Test func rewrittenHeadersRebuildZip64BesideCarriedFields() throws {
        let staleZip64 = Data([0x01, 0x00, 0x08, 0x00]) + Data(repeating: 0xAA, count: 8)
        let unicodePath = Data([0x75, 0x70, 0x06, 0x00, 0x01, 0, 0, 0, 0, 0x61])
        let timestamp = Data([0x55, 0x54, 0x05, 0x00, 0x01, 0x00, 0xF1, 0x53, 0x65])
        let truncated = Data([0x75, 0x78, 0x40, 0x00, 0x01])
        let source = staleZip64 + unicodePath + timestamp + truncated
        #expect(ZipWriter.carriedExtra(source, renamed: false) == unicodePath + timestamp)
        #expect(ZipWriter.carriedExtra(source, renamed: true) == timestamp)

        let offset: UInt64 = 5 << 30
        let header = ZipWriter.centralHeader(
            ZipWriter.CentralRecord(
                versionMadeBy: 0x031E, versionNeeded: 20, flags: 0, method: 0, dosTime: 0, dosDate: 0,
                crc32: 0, compressedSize: 4, uncompressedSize: 4, localHeaderOffset: offset,
                internalAttributes: 0, externalAttributes: 0, nameBytes: Data("a".utf8), extra: timestamp,
                comment: Data()))
        func u16(_ at: Int) -> Int { Int(header[at]) | Int(header[at + 1]) << 8 }
        #expect(u16(6) == 45)
        #expect(header.subdata(in: 42..<46) == Data(repeating: 0xFF, count: 4))
        #expect(u16(30) == 12 + timestamp.count)
        var zip64 = Data([0x01, 0x00, 0x08, 0x00])
        zip64.append(contentsOf: (0..<8).map { UInt8(offset >> ($0 * 8) & 0xff) })
        #expect(header.subdata(in: 47..<(47 + 12 + timestamp.count)) == zip64 + timestamp)
    }

    @Test func computesCRC32AndSHA256Checksums() throws {
        let file = dir.appendingPathComponent("check.txt")
        try Data("123456789".utf8).write(to: file)
        let result = try Checksums.compute(for: file)
        #expect(result.crc32 == 0xcbf4_3926)
        #expect(result.crc32Hex == "CBF43926")
        #expect(result.sha256Hex == "15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225")
    }

    @Test func detectsAndDecodesLegacyFilenameEncodings() throws {
        // Shift-JIS for "日本語.txt"
        let shiftJISBytes: [UInt8] = [0x93, 0xfa, 0x96, 0x7b, 0x8c, 0xea, 0x2e, 0x74, 0x78, 0x74]
        #expect(TextEncoding.auto.decode(Data(shiftJISBytes)) == "日本語.txt")
        #expect(TextEncoding.shiftJIS.decode(Data(shiftJISBytes)) == "日本語.txt")

        let sjisZip = try zip(namedBy: shiftJISBytes)
        let sjisOut = try folder("sjis-out")
        _ = try Archive.extract(sjisZip, into: sjisOut, encoding: .shiftJIS)
        #expect(try Archive.contents(of: sjisOut) == ["日本語.txt"])

        // Windows-1251 for "Привет.txt"
        let win1251Bytes: [UInt8] = [0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2, 0x2e, 0x74, 0x78, 0x74]
        #expect(TextEncoding.windows1251.decode(Data(win1251Bytes)) == "Привет.txt")
        let cyrZip = try zip(namedBy: win1251Bytes)
        let cyrOut = try folder("cyr-out")
        _ = try Archive.extract(cyrZip, into: cyrOut, encoding: .windows1251)
        #expect(try Archive.contents(of: cyrOut) == ["Привет.txt"])
    }

    @Test func verifiesIntactAndCorruptArchives() throws {
        let source = try folder("verify-src")
        try write("hello world", to: "hello.txt", in: source)
        try write("second file", to: "sub/two.txt", in: source)
        let zip = dir.appendingPathComponent("verify.zip")
        try Archive.writeZip(from: source, to: zip)

        let report = try Archive.verify(zip)
        #expect(report.format.hasPrefix("ZIP"))
        #expect(!report.encrypted)
        #expect(report.entryCount >= 2)
        #expect(report.totalBytes == 22)

        // Corrupt a byte inside the compressed data stream and confirm verify catches the bad CRC/stream.
        let catalog = try ZipCatalog.read(from: zip)
        let entry = try #require(catalog.entries.first { $0.path == "hello.txt" })
        let handle = try FileHandle(forReadingFrom: zip)
        let range = try ZipCatalog.payloadRange(in: handle, for: entry)
        try handle.close()
        var bytes = try Data(contentsOf: zip)
        bytes[Int(range.offset)] ^= 0xff
        let corrupt = dir.appendingPathComponent("corrupt.zip")
        try bytes.write(to: corrupt)
        #expect(throws: ArchiveError.self) {
            _ = try Archive.verify(corrupt)
        }
    }

    @Test(arguments: ExportFormat.allCases)
    func exportsToAllSupportedFormats(_ format: ExportFormat) throws {
        let source = try folder("export-src-\(format.rawValue)")
        try write("alpha-export", to: "a.txt", in: source)
        try write("beta-export", to: "nested/b.txt", in: source)

        let out = dir.appendingPathComponent("archive.\(format.fileExtension)")
        try Archive.export(from: source, to: out, format: format, compressionLevel: .balanced)

        let extracted = try folder("export-back-\(format.rawValue)")
        _ = try Archive.extract(out, into: extracted)
        #expect(try read("a.txt", in: extracted) == "alpha-export")
        #expect(try read("nested/b.txt", in: extracted) == "beta-export")
    }

    @Test(arguments: ExportFormat.allCases.filter { $0 != .zip })
    func refusesToExportAPasswordToAFormatThatCannotKeepIt(_ format: ExportFormat) throws {
        let source = try folder("export-locked-\(format.rawValue)")
        try write("secret", to: "a.txt", in: source)
        let out = dir.appendingPathComponent("locked.\(format.fileExtension)")

        #expect(throws: ArchiveError.cantEncrypt(format)) {
            try Archive.export(from: source, to: out, format: format, password: "hunter2")
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
        let explanation = ArchiveError.describe(ArchiveError.cantEncrypt(format), fileName: "secret.zip")
        #expect(explanation.title.contains(".\(format.fileExtension)"))
        #expect(explanation.message.contains("ZIP"))
    }

    @Test func exportsAPasswordToZipEncrypted() throws {
        let source = try folder("export-locked-zip")
        try write("secret", to: "a.txt", in: source)
        let out = dir.appendingPathComponent("locked.zip")
        try Archive.export(from: source, to: out, format: .zip, password: "hunter2")
        #expect(throws: ArchiveError.passwordRequired) { try Archive.extract(out, into: try folder("locked-none")) }
    }

    /// Replaces every occurrence of `placeholder` in the ZIP at `zip`, in both headers, with `raw`.
    func rename(_ placeholder: String, to raw: [UInt8], in zip: URL) throws {
        var bytes = try Data(contentsOf: zip)
        var at = bytes.startIndex
        while let range = bytes.range(of: Data(placeholder.utf8), in: at..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: raw)
            at = range.upperBound
        }
        try bytes.write(to: zip)
    }

    @Test func keepsFlaggedNamesUTF8UnderAChosenEncoding() throws {
        let source = try folder("flagged-src")
        try write("flagged", to: "über.txt", in: source)
        try write("legacy", to: "XXXXX", in: source)
        let zip = dir.appendingPathComponent("flagged.zip")
        try Archive.writeZip(from: source, to: zip)
        // "Ä.txt" in code page 437, unflagged, as an old Windows tool writes it.
        try rename("XXXXX", to: [0x8E] + Array(".txt".utf8), in: zip)
        let catalog = try ZipCatalog.read(from: zip, encoding: .cp437)
        #expect(catalog.entries.first { $0.path.hasSuffix("ber.txt") }?.usesUTF8Flag == true)

        let root = try folder("flagged")
        _ = try Archive.extract(zip, into: root, encoding: .cp437)
        let names = try Archive.contents(of: root).map(\.precomposedStringWithCanonicalMapping)
        #expect(Set(names) == ["über.txt", "Ä.txt"])
        #expect(Set(names) == Set(catalog.entries.map(\.path)))
    }

    @Test func findsDeflate64EntriesUnderAChosenEncoding() throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "zip-deflate64", withExtension: "zip", subdirectory: "Fixtures/matrix"))
        let zip = dir.appendingPathComponent("deflate64.zip")
        try FileManager.default.copyItem(at: fixture, to: zip)
        // Unflagged bytes that are valid UTF-8 ("üg.txt") but mean "├╝g.txt" in code page 437.
        try rename("big.txt", to: [0xC3, 0xBC] + Array("g.txt".utf8), in: zip)

        let root = try folder("deflate64-cp437")
        _ = try Archive.extract(zip, into: root, encoding: .cp437)
        #expect(try Archive.contents(of: root) == ["├╝g.txt"])
        #expect(try Data(contentsOf: root.appendingPathComponent("├╝g.txt")).count == 140_000)
    }

    @Test func mapsEveryFailureToHumanReadableExplanation() {
        let truncated = ArchiveError.describe(
            ArchiveError.unreadable("Truncated input file (needed 1048576 bytes, only 0 available)"),
            fileName: "download.zip"
        )
        #expect(truncated.title.contains("“download.zip”"))
        #expect(truncated.title.contains("incomplete"))
        #expect(truncated.message.contains("downloading"))
        #expect(truncated.technicalDetails?.contains("Truncated input file") == true)

        let corrupt = ArchiveError.describe(
            ArchiveError.unreadable("Unrecognized archive format"),
            fileName: "broken.rar"
        )
        #expect(corrupt.title.contains("“broken.rar”"))
        #expect(corrupt.title.contains("damaged") || corrupt.title.contains("supported"))

        let unsupported = ArchiveError.describe(
            ArchiveError.unreadable("Unsupported compression method"),
            fileName: "novel.zip"
        )
        #expect(unsupported.title.contains("unsupported"))
        #expect(unsupported.message.contains("can’t read yet"))

        let noPerm = ArchiveError.describe(
            CocoaError(.fileWriteNoPermission),
            fileName: "locked.zip"
        )
        #expect(noPerm.title.contains("permission"))
        #expect(noPerm.recovery == .duplicate)

        let diskFull = ArchiveError.describe(
            ArchiveError.noSpace(needed: 500 << 20, available: 10 << 20),
            fileName: "huge.zip"
        )
        #expect(diskFull.title.contains("space"))
        #expect(diskFull.message.contains("“huge.zip”"))

        let wrongPwd = ArchiveError.describe(
            ArchiveError.wrongPassword,
            fileName: "secret.zip"
        )
        #expect(wrongPwd.title.contains("password"))
        #expect(wrongPwd.title.contains("“secret.zip”"))
    }
}

@Suite struct NodeTests {
    @Test func scansSortsAndFilters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyNode-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("docs/old"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: root.appendingPathComponent("docs/report.pdf"))
        try Data(count: 5).write(to: root.appendingPathComponent("docs/old/report 2.pdf"))
        try Data(count: 3).write(to: root.appendingPathComponent("b.txt"))
        try Data(count: 2).write(to: root.appendingPathComponent(".gitignore"))
        try Data(count: 1).write(to: root.appendingPathComponent(".DS_Store"))

        let tree = Node.scan(root)
        tree.sort(by: .name, ascending: true, foldersFirst: false)
        #expect(tree.children.map(\.name) == [".gitignore", "b.txt", "docs"])
        tree.sort(by: .name, ascending: true, foldersFirst: true)
        #expect(tree.children.map(\.name) == ["docs", ".gitignore", "b.txt"])
        #expect(tree.size == 20)
        #expect(tree.find("docs")?.size == 15)
        #expect(tree.find("docs/old/report 2.pdf")?.parent?.name == "old")
        #expect(tree.descendantCount == 6)

        let visibleWithoutDotfiles = try #require(tree.filtered("", showHiddenFiles: false))
        #expect(visibleWithoutDotfiles.children.map(\.name) == ["docs", "b.txt"])
        let visibleWithDotfiles = try #require(tree.filtered("", showHiddenFiles: true))
        #expect(visibleWithDotfiles.children.map(\.name) == ["docs", ".gitignore", "b.txt"])

        tree.sort(by: .size, ascending: false)
        #expect(tree.children.map(\.name) == ["docs", "b.txt", ".gitignore"])

        let found = try #require(tree.filtered("report"))
        #expect(found.children.map(\.name) == ["docs"])
        #expect(found.find("docs/old/report 2.pdf") != nil)
        #expect(found.find("b.txt") == nil)
        #expect(tree.filtered("nothing-like-this")?.children.isEmpty == true)
    }
}
