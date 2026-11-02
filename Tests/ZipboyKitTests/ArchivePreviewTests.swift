import Foundation
import Testing

@testable import ZipboyKit

struct ArchivePreviewTests {
    func fixture(_ name: String, _ subdirectory: String = "Fixtures/matrix") throws -> URL {
        let (base, ext) = ((name as NSString).deletingPathExtension, (name as NSString).pathExtension)
        return try #require(Bundle.module.url(forResource: base, withExtension: ext, subdirectory: subdirectory))
    }

    @Test(arguments: ["zip-deflate.zip", "rar5-compressed.rar", "7z-lzma2.7z", "tar-gzip.tar.gz", "cpio.cpio"])
    func listsWithoutUnpacking(_ name: String) throws {
        let listing = try Archive.list(try fixture(name))
        #expect(!listing.entries.isEmpty, "\(name)")
        #expect(!listing.namesHidden)
        #expect(listing.entries.contains { !$0.isDirectory && $0.size > 0 }, "\(name)")
    }

    @Test func aZipsEncryptedEntriesStillShowTheirNames() throws {
        let listing = try Archive.list(try fixture("zip-aes256.zip"))
        #expect(listing.isEncrypted)
        #expect(!listing.namesHidden)
        #expect(!listing.entries.isEmpty)
    }

    @Test func encryptedNamesAreHiddenNotAnError() throws {
        let listing = try Archive.list(try fixture("encrypted-header.rar", "Fixtures"))
        #expect(listing.namesHidden)
        #expect(ArchivePreview.html(for: listing, name: "x.rar", fileSize: 10).contains("encrypted"))
    }

    @Test func stopsAtTheLimit() throws {
        let listing = try Archive.list(try fixture("7z-lzma2.7z"), limit: 1)
        #expect(listing.entries.count == 1)
        #expect(listing.isTruncated)
    }

    @Test func folderMissingFromTheEntriesStillAppear() {
        let tree = ArchivePreview.tree([
            .init(path: "Top/Inner/a.txt", size: 3, isDirectory: false, modified: nil),
            .init(path: "Top/b.txt", size: 4, isDirectory: false, modified: nil),
        ])
        #expect(tree.folders.keys.sorted() == ["Top"])
        #expect(tree.folders["Top"]?.folders.keys.sorted() == ["Inner"])
        #expect(tree.size == 7)
        #expect(tree.count == 4)
    }

    @Test func namesAreEscaped() {
        let listing = ArchiveListing(
            format: "ZIP", entries: [.init(path: "<script>.txt", size: 1, isDirectory: false, modified: nil)],
            isTruncated: false, isEncrypted: false, namesHidden: false)
        let html = ArchivePreview.html(for: listing, name: "a&b.zip", fileSize: nil)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;.txt"))
        #expect(html.contains("a&amp;b.zip"))
    }

    @Test func tenThousandEntriesRenderQuickly() throws {
        let entries = (0..<10_000).map {
            ArchiveListing.Entry(
                path: "Folder \($0 % 50)/file \($0).txt", size: 1000, isDirectory: false, modified: nil)
        }
        let listing = ArchiveListing(
            format: "ZIP", entries: entries, isTruncated: false, isEncrypted: false, namesHidden: false)
        let started = Date()
        let html = ArchivePreview.html(for: listing, name: "big.zip", fileSize: 1)
        // Generous, to stay clear of a busy CI machine; the measured time goes in the PR.
        #expect(Date().timeIntervalSince(started) < 2)
        #expect(html.contains("10,050 items"))
    }
}

struct FirstImageTests {
    func zip(_ files: [String: Data], password: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString)")
        for (path, data) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let out = dir.appendingPathExtension("zip")
        try Archive.writeZip(from: dir, to: out, password: password)
        return out
    }

    /// Any bytes will do: the finder reads by name and size, and the extension decodes.
    let picture = Data((0..<70_000).map { UInt8($0 % 251) })

    @Test func findsThePictureWholeEvenWhenItIsCompressed() throws {
        let url = try zip(["notes.txt": Data("hi".utf8), "Photos/cover.jpg": picture])
        let found = try #require(Archive.firstImage(in: url))
        #expect(found.path == "Photos/cover.jpg")
        #expect(found.data == picture)
    }

    @Test func noPictureMeansNil() throws {
        #expect(Archive.firstImage(in: try zip(["a.txt": Data("a".utf8)])) == nil)
    }

    @Test func passesOverPicturesTooBigToRead() throws {
        #expect(Archive.firstImage(in: try zip(["big.png": picture]), maxBytes: 1_000) == nil)
    }

    @Test func neverTriesAPassword() throws {
        #expect(Archive.firstImage(in: try zip(["a.png": picture], password: "secret")) == nil)
    }
}
