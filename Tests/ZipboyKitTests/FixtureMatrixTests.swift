import Foundation
import Testing

@testable import ZipboyKit

/// Every variant in `Fixtures/matrix` (from `scripts/make-fixtures`, plus libarchive's RAR files) opens
/// as expected, and every ZIP survives being saved again. The table is the support promise in the README.
@Suite struct FixtureMatrixTests {
    enum Expect {
        /// These paths, with hello.txt and dir/world.txt holding their standard text when listed.
        case opens([String], password: String? = nil)
        /// Fails, and the message contains this.
        case fails(String)
    }

    static let standard = ["dir", "dir/world.txt", "hello.txt"]

    static let cases: [String: Expect] = [
        "zip-store.zip": .opens(standard),
        "zip-deflate.zip": .opens(standard),
        "zip-bzip2.zip": .opens(standard),
        "zip-lzma.zip": .opens(standard),
        "zip-zip64.zip": .opens(standard),
        "zip-data-descriptor.zip": .opens(standard),
        "zip-backslash.zip": .opens(standard),
        "zip-cp437-name.zip": .opens(["über.txt"]),
        "zip-symlink.zip": .opens(["hello.txt", "link"]),
        "zip-empty.zip": .opens([]),
        "zip-zipcrypto.zip": .opens(standard, password: "secret"),
        "zip-aes128.zip": .opens(standard, password: "secret"),
        "zip-aes256.zip": .opens(standard, password: "secret"),
        "zip-deflate64.zip": .fails("deflation-64-bit"),
        "7z-lzma2.7z": .opens(standard),
        "7z-lzma.7z": .opens(standard),
        "7z-ppmd.7z": .opens(standard),
        "7z-bzip2.7z": .opens(standard),
        "7z-deflate.7z": .opens(standard),
        "7z-copy.7z": .opens(standard),
        "7z-solid.7z": .opens(standard),
        "7z-bcj.7z": .opens(standard),
        "tar.tar": .opens(standard),
        "pax.tar": .opens(standard),
        "tar-gzip.tar.gz": .opens(standard),
        "tar-bzip2.tar.bz2": .opens(standard),
        "tar-xz.tar.xz": .opens(standard),
        "tar-lzma.tar.lzma": .opens(standard),
        "cpio.cpio": .opens(standard),
        "iso.iso.gz": .opens(standard),
        "gzip-single.gz": .fails("Unrecognized archive format"),
        "rar4-normal.rar": .opens([
            "LibarchiveAddingTest.html", "testdir", "testdir/LibarchiveAddingTest.html", "testdir/test.txt",
            "testemptydir", "testlink",
        ]),
        "rar4-unicode.rar": .opens([
            "abcdefghijklmnopqrsテスト.txt", "表だよ", "表だよ/ファイル", "表だよ/新しいフォルダ",
            "表だよ/新しいフォルダ/新規テキスト ドキュメント.txt", "表だよ/漢字長いファイル名long-filename-in-漢字.txt",
        ]),
        "rar5-stored.rar": .opens(["helloworld.txt"]),
        "rar5-compressed.rar": .opens(["test.bin"]),
        "rar5-solid.rar": .opens(["test.bin"] + (1...6).map { "test\($0).bin" }),
        "rar5-unicode.rar": .opens(["Ⓗⓐⓡⓓ Ⓛⓘⓝⓚ.txt", "𝒮𝓎𝓂𝒷𝑜𝓁𝒾𝒸 𝐿𝒾𝓃𝓀.txt", "👋🌎.txt"]),
        "rar5-symlink.rar": .opens(["dir", "dirlink", "file.txt", "symlink.txt"]),
    ]

    static let matrix = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/matrix")

    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyMatrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Paths in composed form, since APFS hands back names in whatever form they were written.
    func listing(_ root: URL) throws -> [String] {
        try Archive.contents(of: root).map(\.precomposedStringWithCanonicalMapping).sorted()
    }

    @Test func everyFixtureHasACase() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.matrix.path).sorted()
        #expect(files == Self.cases.keys.sorted())
    }

    @Test(arguments: cases.keys.sorted())
    func opensAsPromised(_ name: String) throws {
        let url = Self.matrix.appendingPathComponent(name)
        let root = try scratch()
        switch try #require(Self.cases[name]) {
        case .fails(let words):
            #expect {
                try Archive.extract(url, into: root)
            } throws: { error in
                (error as? ArchiveError)?.errorDescription?.contains(words) == true
            }
        case .opens(let paths, let password):
            if password != nil {
                #expect(throws: ArchiveError.passwordRequired) { try Archive.extract(url, into: try scratch()) }
            }
            _ = try Archive.extract(url, into: root, password: password)
            #expect(try listing(root) == paths.map(\.precomposedStringWithCanonicalMapping).sorted())
            if paths.contains("hello.txt") {
                #expect(try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8) == "hello\n")
            }
            if paths.contains("dir/world.txt") {
                #expect(
                    try String(contentsOf: root.appendingPathComponent("dir/world.txt"), encoding: .utf8) == "world\n")
            }
            if name == "zip-symlink.zip" {
                #expect(
                    try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("link").path)
                        == "hello.txt")
            }
            if name.hasSuffix(".zip") { try roundTrips(root) }
        }
    }

    /// Saving what was opened and opening it again gives back the same names and the same bytes.
    func roundTrips(_ root: URL) throws {
        let saved = try scratch().appendingPathComponent("saved.zip")
        try Archive.writeZip(from: root, to: saved)
        let again = try scratch()
        _ = try Archive.extract(saved, into: again)
        #expect(try listing(again) == listing(root))
        for path in try Archive.contents(of: root) {
            let before = root.appendingPathComponent(path), after = again.appendingPathComponent(path)
            if (try? before.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                #expect(try Data(contentsOf: before) == Data(contentsOf: after), "\(path)")
            }
        }
    }
}
