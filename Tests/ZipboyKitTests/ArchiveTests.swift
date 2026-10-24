import Foundation
import Testing

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

    @Test func reportsGarbage() throws {
        let junk = dir.appendingPathComponent("junk.zip")
        try Data("not an archive".utf8).write(to: junk)
        #expect(throws: ArchiveError.self) { try Archive.extract(junk, into: try folder("x")) }
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
        try Data(count: 1).write(to: root.appendingPathComponent(".DS_Store"))

        let tree = Node.scan(root)
        tree.sort(by: .name, ascending: true)
        #expect(tree.children.map(\.name) == ["b.txt", "docs"])
        #expect(tree.size == 18)
        #expect(tree.find("docs")?.size == 15)
        #expect(tree.find("docs/old/report 2.pdf")?.parent?.name == "old")
        #expect(tree.descendantCount == 5)

        tree.sort(by: .size, ascending: false)
        #expect(tree.children.map(\.name) == ["docs", "b.txt"])

        let found = try #require(tree.filtered("report"))
        #expect(found.children.map(\.name) == ["docs"])
        #expect(found.find("docs/old/report 2.pdf") != nil)
        #expect(found.find("b.txt") == nil)
        #expect(tree.filtered("nothing-like-this")?.children.isEmpty == true)
    }
}
