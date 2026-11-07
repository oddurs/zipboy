import AppKit
import CryptoKit
import Darwin
import Foundation
import Testing
import ZipboyKit

@testable import Zipboy

/// The document's file handling, run against real archives in a temporary folder.
@MainActor
@Suite struct DocumentTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Reads as NSDocumentController would, then waits for the background unpacking to finish.
    func open(_ url: URL, type: String) async throws -> ArchiveDocument {
        let document = ArchiveDocument()
        document.fileURL = url
        document.fileType = type
        try document.read(from: url, ofType: type)
        for _ in 0..<500 where document.loading != nil || document.tree == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(document.loading == nil)
        return document
    }

    @Test func runsFinderServicesOffTheMainThread() async {
        let ranOnMain = Locked<Bool?>(nil)
        await AppDelegate().runService {
            ranOnMain.value = Thread.isMainThread
            return []
        }.value
        #expect(ranOnMain.value == false)
    }

    @Test func opensARarAsANewDocumentSoAutosaveCannotReplaceIt() async throws {
        let fixture = BundleTests.root.appendingPathComponent("Tests/ZipboyKitTests/Fixtures/container.rar")
        let rar = dir.appendingPathComponent("container.rar")
        try FileManager.default.copyItem(at: fixture, to: rar)

        let document = try await open(rar, type: "com.rarlab.rar-archive")
        defer { document.close() }
        // With a file URL left on the RAR, autosaving in place wrote a ZIP over it and deleted the RAR.
        #expect(document.fileURL == nil)
        #expect(document.fileType == ArchiveDocument.zipType)
        #expect(document.importedFrom?.format == "RAR")
        #expect(document.displayName == "container")
        #expect(document.source == rar)
        #expect(document.tree?.children.map(\.name) == ["container"])
        #expect(try Data(contentsOf: rar) == Data(contentsOf: fixture))
    }

    @Test func opensAZipInPlace() async throws {
        let source = dir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: source.appendingPathComponent("a.txt"))
        let zip = dir.appendingPathComponent("Plain.zip")
        try Archive.writeZip(from: source, to: zip)

        let document = try await open(zip, type: ArchiveDocument.zipType)
        defer { document.close() }
        #expect(document.fileURL == zip)
        #expect(document.importedFrom == nil)
        #expect(document.tree?.children.map(\.name) == ["a.txt"])
    }

    @Test func editsUndoAndCount() async throws {
        let source = dir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: source.appendingPathComponent("a.txt"))
        let zip = dir.appendingPathComponent("Edit.zip")
        try Archive.writeZip(from: source, to: zip)
        let document = try await open(zip, type: ArchiveDocument.zipType)
        defer { document.close() }

        // In the app each edit arrives as its own event; here they are grouped by hand to match.
        let undo = try #require(document.undoManager)
        undo.groupsByEvent = false
        func step(_ edit: () throws -> Void) rethrows {
            undo.beginUndoGrouping()
            defer { undo.endUndoGrouping() }
            try edit()
        }
        var folder = ""
        try step { folder = try document.newFolder(in: "") }
        try step { try document.move(["a.txt"], into: folder) }
        #expect(document.tree?.find("untitled folder/a.txt") != nil)
        try step { try document.rename("untitled folder", to: "Docs") }
        try step { try document.remove(["Docs/a.txt"]) }
        #expect(document.tree?.find("Docs")?.children.isEmpty == true)

        // Each edit is its own step, so undo walks back through them in order.
        undo.undo()
        #expect(document.tree?.find("Docs/a.txt") != nil)
        undo.undo()
        #expect(document.tree?.find("untitled folder/a.txt") != nil)
        undo.redo()
        #expect(document.tree?.find("Docs/a.txt") != nil)
    }

    @Test func addingReadOnlyItemsMakesThemEditableInWorkspace() async throws {
        let source = dir.appendingPathComponent("readonly-source")
        let lockedFolder = source.appendingPathComponent("LockedDir")
        try FileManager.default.createDirectory(at: lockedFolder, withIntermediateDirectories: true)
        let lockedFile = lockedFolder.appendingPathComponent("readonly.txt")
        try Data("locked".utf8).write(to: lockedFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: lockedFile.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedFolder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedFile.path)
        }

        let document = ArchiveDocument()
        document.makeWindowControllers()
        defer { document.close() }

        try await document.add([lockedFolder], into: "") { _ in .keepBoth }
        #expect(document.tree?.find("LockedDir/readonly.txt") != nil)
        try document.rename("LockedDir/readonly.txt", to: "writable.txt")
        #expect(document.tree?.find("LockedDir/writable.txt") != nil)
        try document.remove(["LockedDir"])
        #expect(document.tree?.children.isEmpty == true)
    }

    @Test func mapsArchiveExtensionsToSafeDocumentTypes() throws {
        let controller = DocumentController()
        #expect(try controller.typeForContents(of: URL(fileURLWithPath: "/tmp/a.zip")) == ArchiveDocument.zipType)
        for ext in [
            "rar", "7z", "tar", "tgz", "tbz2", "txz", "tlz", "taz", "cpgz", "xar", "cab", "lha", "deb", "zipx",
        ] {
            let type = try controller.typeForContents(of: URL(fileURLWithPath: "/tmp/sample.\(ext)"))
            #expect(type == "public.archive", "\(ext)")
        }
        for unsupported in ["zst", "tzst", "lz4", "lzo"] {
            #expect(!ZipMethod.archiveExtensions.contains(unsupported), "\(unsupported)")
        }
    }
}

/// The save path: snapshots, autosaves cancelled by edits, and encryption.
@MainActor
@Suite struct SaveTests {
    let dir: URL

    init() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboySaves-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// A ZIP holding `files`, opened as a document.
    func document(_ files: [String: Data]) async throws -> ArchiveDocument {
        let source = dir.appendingPathComponent("source-\(UUID().uuidString)")
        for (name, data) in files {
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try data.write(to: source.appendingPathComponent(name))
        }
        let zip = dir.appendingPathComponent("\(UUID().uuidString).zip")
        try Archive.writeZip(from: source, to: zip)
        let document = ArchiveDocument()
        document.fileURL = zip
        document.fileType = ArchiveDocument.zipType
        try document.read(from: zip, ofType: ArchiveDocument.zipType)
        for _ in 0..<500 where document.loading != nil || document.tree == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        return document
    }

    /// How a save ended. Filled in on the main thread by the save's completion handler.
    final class Outcome: @unchecked Sendable {
        var finished = false
        var error: Error?
    }

    /// Starts a save and returns at once, as AppKit does once the snapshot is taken, so the caller can
    /// edit while it runs.
    func begin(_ document: ArchiveDocument, to url: URL, as operation: NSDocument.SaveOperationType) -> Outcome {
        let outcome = Outcome()
        document.save(to: url, ofType: ArchiveDocument.zipType, for: operation) { error in
            outcome.error = error
            outcome.finished = true
        }
        return outcome
    }

    func finish(_ outcome: Outcome) async throws -> Error? {
        for _ in 0..<3000 where !outcome.finished { try await Task.sleep(for: .milliseconds(10)) }
        #expect(outcome.finished)
        return outcome.error
    }

    func save(_ document: ArchiveDocument, to url: URL, as operation: NSDocument.SaveOperationType) async throws
        -> Error?
    {
        try await finish(begin(document, to: url, as: operation))
    }

    func names(in zip: URL, password: String? = nil) throws -> [String] {
        let root = dir.appendingPathComponent("read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: root, password: password)
        return try Archive.contents(of: root)
    }

    @Test func anEditDuringASaveWaitsForTheNextOne() async throws {
        let document = try await document(["a.txt": Data("a".utf8)])
        defer { document.close() }
        let first = dir.appendingPathComponent("first.zip")
        let pending = begin(document, to: first, as: .saveToOperation)
        // The snapshot was taken when the save began, so this edit belongs to the next one.
        _ = try document.newFolder(in: "")
        #expect(try await finish(pending) == nil)
        #expect(try names(in: first) == ["a.txt"])

        let second = dir.appendingPathComponent("second.zip")
        #expect(try await save(document, to: second, as: .saveToOperation) == nil)
        #expect(try names(in: second) == ["a.txt", "untitled folder"])
    }

    @Test func anEditCancelsAnAutosaveAndLeavesTheFileAlone() async throws {
        // Big enough that writing it takes far longer than the edit that follows.
        let noise = try #require(FileHandle(forReadingAtPath: "/dev/urandom")).readData(ofLength: 48 << 20)
        let document = try await document(["noise.bin": noise])
        defer { document.close() }
        let original = try #require(document.fileURL)
        let before = try Data(contentsOf: original)

        let pending = begin(document, to: original, as: .autosaveInPlaceOperation)
        _ = try document.newFolder(in: "")
        let error = try await finish(pending)
        #expect((error as? CocoaError)?.code == .userCancelled)
        #expect(try Data(contentsOf: original) == before)
    }

    @Test func savesEncryptedWithThePasswordAndPlainWithout() async throws {
        let document = try await document(["secret.txt": Data("s".utf8)])
        defer { document.close() }

        document.setPassword("hunter2")
        let locked = dir.appendingPathComponent("locked.zip")
        #expect(try await save(document, to: locked, as: .saveToOperation) == nil)
        #expect(throws: ArchiveError.passwordRequired) { try names(in: locked) }
        #expect(try names(in: locked, password: "hunter2") == ["secret.txt"])
        // WinZip's AES extra field (0x9901, 7 bytes), vendor version, "AE", and strength 3: AES-256.
        let aes256 = Data([0x01, 0x99, 0x07, 0x00]) + Data([0x02, 0x00, 0x41, 0x45, 0x03])
        #expect(try Data(contentsOf: locked).range(of: aes256) != nil)

        document.setPassword(nil)
        let plain = dir.appendingPathComponent("plain.zip")
        #expect(try await save(document, to: plain, as: .saveToOperation) == nil)
        #expect(try names(in: plain) == ["secret.txt"])
    }

    @Test func deltaSavePreservesUnchangedEntriesByteForByteAcrossEdits() async throws {
        let payloadKeep = Data((0..<8192).map { UInt8(($0 * 73) & 0xff) })
        let payloadRename = Data("rename-without-recompressing-payload".utf8)
        let document = try await document([
            "keep.bin": payloadKeep,
            "old.txt": payloadRename,
            "remove.txt": Data("gone".utf8),
        ])
        defer { document.close() }

        let zip = try #require(document.fileURL)
        let beforeCatalog = try ZipCatalog.read(from: zip)
        let beforeKeep = try #require(beforeCatalog.entries.first { $0.path == "keep.bin" })
        let beforeHandle = try FileHandle(forReadingFrom: zip)
        let beforeRange = try ZipCatalog.payloadRange(in: beforeHandle, for: beforeKeep)
        try beforeHandle.seek(toOffset: beforeRange.offset)
        let beforeCompressed = try #require(try beforeHandle.read(upToCount: Int(beforeRange.length)))
        try beforeHandle.close()

        try document.rename("old.txt", to: "renamed.txt")
        try document.remove(["remove.txt"])
        let addedURL = dir.appendingPathComponent("fresh.txt")
        try Data("fresh-addition".utf8).write(to: addedURL)
        try await document.add([addedURL], into: "") { _ in .replace }

        #expect(try await save(document, to: zip, as: .saveOperation) == nil)

        let afterCatalog = try ZipCatalog.read(from: zip)
        let afterKeep = try #require(afterCatalog.entries.first { $0.path == "keep.bin" })
        let afterHandle = try FileHandle(forReadingFrom: zip)
        let afterRange = try ZipCatalog.payloadRange(in: afterHandle, for: afterKeep)
        try afterHandle.seek(toOffset: afterRange.offset)
        let afterCompressed = try #require(try afterHandle.read(upToCount: Int(afterRange.length)))
        try afterHandle.close()

        #expect(afterCompressed == beforeCompressed)
        #expect(try names(in: zip) == ["fresh.txt", "keep.bin", "renamed.txt"])

        // A second consecutive edit + save in place must also succeed using refreshed catalog tracking.
        _ = try document.newFolder(in: "")
        #expect(try await save(document, to: zip, as: .saveOperation) == nil)
        #expect(try names(in: zip) == ["fresh.txt", "keep.bin", "renamed.txt", "untitled folder"])
    }

    @Test func aFileReplacedDuringASaveReachesTheNextOne() async throws {
        // Big enough that the replacement lands while the first save is still writing.
        let noise = try #require(FileHandle(forReadingAtPath: "/dev/urandom")).readData(ofLength: 48 << 20)
        let document = try await document(["noise.bin": noise, "notes.txt": Data("old".utf8)])
        defer { document.close() }
        let zip = try #require(document.fileURL)

        let pending = begin(document, to: zip, as: .saveOperation)
        let fresh = dir.appendingPathComponent("notes.txt")
        try Data("new content".utf8).write(to: fresh)
        try await document.add([fresh], into: "") { _ in .replace }
        #expect(try await finish(pending) == nil)
        // Still a delta save for what didn't change; only the replaced file loses its entry.
        #expect(document.verbatimEntry(forPath: "noise.bin") != nil)
        #expect(document.verbatimEntry(forPath: "notes.txt") == nil)
        #expect(try await save(document, to: zip, as: .saveOperation) == nil)

        let root = dir.appendingPathComponent("read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: root)
        let saved = try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8)
        #expect(saved == "new content")
    }

    @Test func renamedAndMovedFilesKeepCompressedPayloadAndUndoRedoTracksEntries() async throws {
        let fm = FileManager.default
        let srcFolder = dir.appendingPathComponent("tracking-src")
        try fm.createDirectory(at: srcFolder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: srcFolder.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: srcFolder.appendingPathComponent("dest"), withIntermediateDirectories: true)

        let bodyA = Data(String(repeating: "alpha-compressible-payload\n", count: 250).utf8)
        let bodyB = Data(String(repeating: "bravo-movable-payload\n", count: 250).utf8)
        let bodyC = Data(String(repeating: "charlie-folder-payload\n", count: 250).utf8)
        let bodyReplace = Data("same-len-123".utf8)
        try bodyA.write(to: srcFolder.appendingPathComponent("a.txt"))
        try bodyB.write(to: srcFolder.appendingPathComponent("sub/b.txt"))
        try bodyC.write(to: srcFolder.appendingPathComponent("folder/c.txt"))
        try bodyReplace.write(to: srcFolder.appendingPathComponent("inplace.txt"))

        // Compress at .best so recompressing at default .balanced would produce different deflate bytes.
        let zip = dir.appendingPathComponent("tracking.zip")
        try Archive.writeZip(from: srcFolder, to: zip, compressionLevel: .best)

        func compressedBytes(of path: String, in archive: URL) throws -> Data {
            let catalog = try ZipCatalog.read(from: archive)
            let entry = try #require(catalog.entries.first { $0.path == path })
            let handle = try FileHandle(forReadingFrom: archive)
            defer { try? handle.close() }
            let range = try ZipCatalog.payloadRange(in: handle, for: entry)
            try handle.seek(toOffset: range.offset)
            return try #require(try handle.read(upToCount: Int(range.length)))
        }

        let origCompressedA = try compressedBytes(of: "a.txt", in: zip)
        let origCompressedB = try compressedBytes(of: "sub/b.txt", in: zip)
        let origCompressedC = try compressedBytes(of: "folder/c.txt", in: zip)

        let document = ArchiveDocument()
        document.fileURL = zip
        document.fileType = ArchiveDocument.zipType
        try document.read(from: zip, ofType: ArchiveDocument.zipType)
        for _ in 0..<500 where document.loading != nil || document.tree == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { document.close() }
        guard let undo = document.undoManager else {
            Issue.record("Expected NSDocument undoManager")
            return
        }
        undo.groupsByEvent = false

        // 1. Rename file, move file into another folder, and rename a parent folder.
        undo.beginUndoGrouping()
        try document.rename("a.txt", to: "alpha.txt")
        undo.endUndoGrouping()
        #expect(document.verbatimEntry(forPath: "a.txt") == nil)
        #expect(document.verbatimEntry(forPath: "alpha.txt")?.path == "a.txt")

        undo.beginUndoGrouping()
        try document.move(["sub/b.txt"], into: "dest")
        undo.endUndoGrouping()
        #expect(document.verbatimEntry(forPath: "sub/b.txt") == nil)
        #expect(document.verbatimEntry(forPath: "dest/b.txt")?.path == "sub/b.txt")

        undo.beginUndoGrouping()
        try document.rename("folder", to: "renamed-folder")
        undo.endUndoGrouping()
        #expect(document.verbatimEntry(forPath: "folder/c.txt") == nil)
        #expect(document.verbatimEntry(forPath: "renamed-folder/c.txt")?.path == "folder/c.txt")

        // Undo & redo across all three moves keep verbatim entry mappings intact.
        undo.undo()  // undo folder rename
        #expect(document.verbatimEntry(forPath: "folder/c.txt")?.path == "folder/c.txt")
        undo.undo()  // undo move
        #expect(document.verbatimEntry(forPath: "sub/b.txt")?.path == "sub/b.txt")
        undo.undo()  // undo file rename
        #expect(document.verbatimEntry(forPath: "a.txt")?.path == "a.txt")

        undo.redo()
        undo.redo()
        undo.redo()
        #expect(document.verbatimEntry(forPath: "alpha.txt")?.path == "a.txt")
        #expect(document.verbatimEntry(forPath: "dest/b.txt")?.path == "sub/b.txt")
        #expect(document.verbatimEntry(forPath: "renamed-folder/c.txt")?.path == "folder/c.txt")

        // Delete + undo + redo + undo preserves verbatim mapping from holding area.
        undo.beginUndoGrouping()
        try document.remove(["alpha.txt"])
        undo.endUndoGrouping()
        #expect(document.verbatimEntry(forPath: "alpha.txt") == nil)
        undo.undo()
        #expect(document.verbatimEntry(forPath: "alpha.txt")?.path == "a.txt")
        undo.redo()
        #expect(document.verbatimEntry(forPath: "alpha.txt") == nil)
        undo.undo()
        #expect(document.verbatimEntry(forPath: "alpha.txt")?.path == "a.txt")

        // Save after rename + move: compressed bytes are copied verbatim under the new names.
        #expect(try await save(document, to: zip, as: .saveOperation) == nil)
        #expect(try compressedBytes(of: "alpha.txt", in: zip) == origCompressedA)
        #expect(try compressedBytes(of: "dest/b.txt", in: zip) == origCompressedB)
        #expect(try compressedBytes(of: "renamed-folder/c.txt", in: zip) == origCompressedC)

        let checkDir1 = dir.appendingPathComponent("check-1")
        try fm.createDirectory(at: checkDir1, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: checkDir1)
        #expect(try Data(contentsOf: checkDir1.appendingPathComponent("alpha.txt")) == bodyA)
        #expect(try Data(contentsOf: checkDir1.appendingPathComponent("dest/b.txt")) == bodyB)
        #expect(try Data(contentsOf: checkDir1.appendingPathComponent("renamed-folder/c.txt")) == bodyC)

        // 2. Replace + undo + redo + post-save undo keeps tracking accurate at every step.
        let replacementURL = dir.appendingPathComponent("alpha.txt")
        let replacementData = Data("replaced-alpha-content".utf8)
        try replacementData.write(to: replacementURL)

        undo.beginUndoGrouping()
        try await document.add([replacementURL], into: "") { _ in Prompts.Resolution.replace }
        undo.endUndoGrouping()
        #expect(document.verbatimEntry(forPath: "alpha.txt") == nil)

        // Undo before save restores the original inode, matching the saved entry again.
        undo.undo()
        #expect(document.verbatimEntry(forPath: "alpha.txt")?.path == "alpha.txt")

        // Redo puts the replacement back; saving writes the replacement and refreshes tracking.
        undo.redo()
        #expect(document.verbatimEntry(forPath: "alpha.txt") == nil)
        #expect(try await save(document, to: zip, as: .saveOperation) == nil)

        // Undoing AFTER a save restores the older inode (no longer in zip), so it must recompress cleanly.
        undo.undo()
        #expect(document.verbatimEntry(forPath: "alpha.txt") == nil)

        // Immediate same-length in-place overwrite (sub-millisecond) must also invalidate verbatimEntry.
        _ = try await document.materialize(["inplace.txt"])
        let inplaceLive = try #require(document.workspace).contents.appendingPathComponent("inplace.txt")
        #expect(document.verbatimEntry(forPath: "inplace.txt") != nil)
        let inplaceHandle = try FileHandle(forWritingTo: inplaceLive)
        try inplaceHandle.write(contentsOf: Data("diff-len-123".utf8))
        try inplaceHandle.close()
        #expect(document.verbatimEntry(forPath: "inplace.txt") == nil)

        #expect(try await save(document, to: zip, as: .saveOperation) == nil)
        let checkDir2 = dir.appendingPathComponent("check-2")
        try fm.createDirectory(at: checkDir2, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: checkDir2)
        #expect(try Data(contentsOf: checkDir2.appendingPathComponent("alpha.txt")) == bodyA)
        #expect(
            try Data(contentsOf: checkDir2.appendingPathComponent("inplace.txt")) == Data("diff-len-123".utf8))
    }

    @Test func fallsBackToFullWriteWithLogWhenSourceArchiveChangedOnDisk() async throws {
        let fm = FileManager.default
        let payloadKeep = Data(String(repeating: "keep-workspace-copy\n", count: 200).utf8)
        let document = try await document([
            "keep.txt": payloadKeep,
            "note.txt": Data("initial".utf8),
        ])
        defer { document.close() }

        let zip = try #require(document.fileURL)
        let logs = Locked<[String]>([])
        document.onSaveLog = { line in
            var current = logs.value
            current.append(line)
            logs.value = current
        }

        // Replace the source archive on disk behind the document's back with an unrelated archive.
        // If delta save tried to copy verbatim from `zip`, it would read garbage or fail; falling
        // back to a full write from the unpacked workspace snapshot produces a valid archive.
        let rogueDir = dir.appendingPathComponent("rogue-src")
        try fm.createDirectory(at: rogueDir, withIntermediateDirectories: true)
        try Data("rogue".utf8).write(to: rogueDir.appendingPathComponent("rogue.txt"))
        try Archive.writeZip(from: rogueDir, to: zip)

        let addedURL = dir.appendingPathComponent("added.txt")
        try Data("added-in-workspace".utf8).write(to: addedURL)
        try await document.add([addedURL], into: "") { _ in Prompts.Resolution.replace }

        #expect(try await save(document, to: zip, as: .saveOperation) == nil)
        #expect(logs.value.count == 1)
        #expect(logs.value.first?.contains(zip.lastPathComponent) == true)
        #expect(logs.value.first?.contains("falling back to full write") == true)

        let extracted = dir.appendingPathComponent("fallback-extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: extracted)
        #expect(try Archive.contents(of: extracted) == ["added.txt", "keep.txt", "note.txt"])
        #expect(try Data(contentsOf: extracted.appendingPathComponent("keep.txt")) == payloadKeep)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("added.txt")) == Data("added-in-workspace".utf8))

        // After the fallback save completes in place, provenance is refreshed to the newly written archive,
        // so the next save uses ZipWriter again without logging a fallback.
        _ = try document.newFolder(in: "")
        #expect(try await save(document, to: zip, as: .saveOperation) == nil)
        #expect(logs.value.count == 1)
        #expect(try names(in: zip) == ["added.txt", "keep.txt", "note.txt", "untitled folder"])
    }

    @Test func nestedArchiveTracksParentAndFinderServicesRoundTrip() async throws {
        let parentDoc = try await document(["outer.txt": Data("outer".utf8)])
        defer { parentDoc.close() }
        let childDoc = try await document(["inner.txt": Data("inner".utf8)])
        defer { childDoc.close() }

        childDoc.parentDocument = parentDoc
        #expect(childDoc.displayName.contains("—"))
        let childZip = try #require(childDoc.fileURL)
        #expect(try await save(childDoc, to: childZip, as: .saveOperation) == nil)
        #expect(parentDoc.isDocumentEdited)

        // Finder Services: compress and extract round-trip.
        let serviceDir = dir.appendingPathComponent("services")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        let sample = serviceDir.appendingPathComponent("sample.txt")
        try Data("service-payload".utf8).write(to: sample)

        let createdZip = try AppDelegate.compressFiles([sample], into: serviceDir)
        #expect(createdZip.lastPathComponent == "sample.zip")

        let extractDir = dir.appendingPathComponent("services-out")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let extracted = try AppDelegate.extractArchives([createdZip], into: extractDir)
        #expect(!extracted.isEmpty)

        // File promise provider materializes a promised node to a destination URL.
        let browser = BrowserViewController()
        let promisedNode = try #require(childDoc.tree?.find("inner.txt"))
        let provider = browser.filePromiseProvider(for: promisedNode)
        #expect(browser.filePromiseProvider(provider, fileNameForType: "public.plain-text") == "inner.txt")
        let dest = dir.appendingPathComponent("promised-out.txt")
        var writeError: Error?
        browser.filePromiseProvider(provider, writePromiseTo: dest) { writeError = $0 }
        #expect(writeError == nil)
        #expect(try Data(contentsOf: dest) == Data("inner".utf8))
    }
}

/// Long adds and extracts show how far they've got and stop cleanly.
@MainActor
@Suite(.serialized) struct LongTaskTests {
    func bigFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("long-\(UUID().uuidString)/Big")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 0..<3 { try Data(count: 2 << 20).write(to: dir.appendingPathComponent("part \(index).bin")) }
        return dir
    }

    @Test func stoppingAnAddLeavesTheArchiveAsItWas() async throws {
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        doc.cloneWhenCopying = false
        // Stops the moment the add announces itself, before a byte is staged.
        doc.onStatus = { doc.tasks.last?.progress.cancel() }
        await #expect(throws: ArchiveError.cancelled) {
            try await doc.add([try bigFolder()], into: "") { _ in .keepBoth }
        }
        #expect(doc.tree?.children.isEmpty == true)
        #expect(doc.tasks.isEmpty)
        #expect(doc.activity == nil)
    }

    @Test func anAddCountsItsBytes() async throws {
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        doc.cloneWhenCopying = false
        var seen: LongTask?
        doc.onStatus = { if let task = doc.tasks.last { seen = task } }
        try await doc.add([try bigFolder()], into: "") { _ in .keepBoth }
        let task = try #require(seen)
        #expect(task.progress.totalUnitCount == 3 * (2 << 20))
        #expect(task.progress.fractionCompleted == 1)
        #expect(doc.tree?.find("Big/part 2.bin") != nil)
    }

    @Test func stoppingAnExtractRemovesWhatItCopied() throws {
        let source = try bigFolder()
        let out = source.deletingLastPathComponent().appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let progress = Progress(totalUnitCount: 3 * (2 << 20))
        let calls = Locked(0)
        // Stops partway through the second file, after the first is in place.
        let files = (0..<3).map { source.appendingPathComponent("part \($0).bin") }
        let watcher = progress.observe(\.completedUnitCount) { progress, _ in
            calls.value += 1
            if progress.completedUnitCount > (2 << 20) { progress.cancel() }
        }
        defer { watcher.invalidate() }
        #expect(throws: ArchiveError.cancelled) {
            _ = try BrowserViewController.copy(files, into: out, progress: progress, clone: false)
        }
        #expect(calls.value > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test func theBarWaitsASecondThenShowsAndGoes() throws {
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        let controller = try #require(doc.windowControllers.first as? ArchiveWindowController)
        let task = doc.beginTask("Extracting “x”…", total: 100)
        controller.showTask(now: task.started.addingTimeInterval(0.5))
        #expect(controller.taskBar.isHidden)
        controller.showTask(now: task.started.addingTimeInterval(1.5))
        #expect(!controller.taskBar.isHidden)
        #expect(doc.activity == "Extracting “x”…")

        // Escape reaches the document through the window controller.
        controller.cancelOperation(nil)
        #expect(task.progress.isCancelled)
        doc.endTask(task)
        controller.showTask()
        #expect(controller.taskBar.isHidden)
        #expect(doc.activity == nil)
    }
}

@MainActor
final class RecordingNotifier: Notifier {
    var posted: [(String, String)] = []
    func finished(_ what: String, archive: String) { posted.append((what, archive)) }
}

/// Long work shows on the Dock, and says when it's finished out of sight.
@MainActor
@Suite(.serialized) struct TaskWatcherTests {
    let notifier = RecordingNotifier()

    func finish(frontmost: Bool, ranFor seconds: TimeInterval, cancelled: Bool = false) throws -> ArchiveDocument {
        // A watcher of its own, so another suite's work can't post to this one's notifier.
        let watcher = TaskWatcher()
        watcher.notifier = notifier
        watcher.isFrontmost = { frontmost }
        let doc = ArchiveDocument()
        doc.makeWindowControllers()
        // Backdated rather than waited for, so the test takes no time.
        let backdated = LongTask(
            title: "Extracting “Photos.zip”…", total: 10, started: Date().addingTimeInterval(-seconds))
        if cancelled { backdated.progress.cancel() }
        watcher.began(backdated)
        watcher.ended(backdated, in: doc)
        return doc
    }

    @Test func finishingOutOfSightPostsOneNoticeNamingTheArchive() throws {
        let doc = try finish(frontmost: false, ranFor: 3)
        defer { doc.close() }
        #expect(notifier.posted.count == 1)
        #expect(notifier.posted.first?.0 == "Extracting “Photos.zip”")
        #expect(notifier.posted.first?.1 == doc.displayName)
    }

    @Test func finishingInViewQuicklyOrStoppedPostsNothing() throws {
        for doc in [
            try finish(frontmost: true, ranFor: 3), try finish(frontmost: false, ranFor: 0.2),
            try finish(frontmost: false, ranFor: 3, cancelled: true),
        ] { doc.close() }
        #expect(notifier.posted.isEmpty)
    }

    @Test func theDockShowsOneBarForEverythingRunning() throws {
        // A watcher of its own: other suites' adds run alongside and report to the shared one.
        let watcher = TaskWatcher()
        let doc = ArchiveDocument()
        let first = LongTask(title: "Adding", total: 100)
        let second = LongTask(title: "Extracting", total: 300)
        watcher.began(first)
        watcher.began(second)
        first.progress.completedUnitCount = 100
        second.progress.completedUnitCount = 100
        watcher.refresh()
        #expect(watcher.fraction == 0.5)
        #expect(watcher.tile.view?.fraction == 0.5)

        watcher.ended(first, in: doc)
        watcher.ended(second, in: doc)
        #expect(watcher.fraction == nil)
        #expect(watcher.tile.view == nil)
    }

    @Test func clickingANoticeBringsItsArchiveForward() throws {
        let doc = ArchiveDocument()
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        defer { doc.close() }
        #expect(TaskWatcher.bringForward(archiveNamed: doc.displayName) === doc)
        #expect(doc.windowControllers.first?.window?.isVisible == true)
        #expect(TaskWatcher.bringForward(archiveNamed: "Nothing by this name") == nil)
    }
}

/// What AppleScript's `extract` and `compress` do, run directly rather than through an Apple event.
@Suite struct ScriptingTests {
    func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("b.txt"))
        return dir
    }

    @Test func compressThenExtractRoundTrips() throws {
        let dir = try folder()
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let zip = try Scripting.compress(
            [dir.appendingPathComponent("a.txt"), dir.appendingPathComponent("b.txt")], into: out)
        #expect(zip.pathExtension == "zip")
        #expect(zip.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)

        let unpacked = dir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let results = try Scripting.extract(zip, to: unpacked)
        #expect(!results.isEmpty)
        let names = try FileManager.default.subpathsOfDirectory(atPath: unpacked.path)
        #expect(names.contains { $0.hasSuffix("a.txt") } && names.contains { $0.hasSuffix("b.txt") })
    }

    @Test func aMissingPathIsNamedInTheError() throws {
        let gone = URL(fileURLWithPath: "/tmp/zipboy-not-here-\(UUID().uuidString).zip")
        do {
            _ = try Scripting.extract(gone, to: nil)
            Issue.record("extracted a file that isn't there")
        } catch {
            let (number, message) = Scripting.scriptError(for: error)
            #expect(number == -43)
            #expect(message.contains(gone.path))
        }
    }

    @Test func takesOneFileOrAList() {
        let a = URL(fileURLWithPath: "/a")
        #expect(Scripting.urls(from: a) == [a])
        #expect(Scripting.urls(from: [a, a] as [Any]) == [a, a])
        #expect(Scripting.urls(from: "not a file").isEmpty)
    }
}

/// Offering a newer Zipboy, with the network and the defaults replaced.
@MainActor
@Suite struct UpdaterTests {
    func updater(latest: String, disk: Data = Data("image".utf8), sum: String? = nil) -> Updater {
        let updater = Updater()
        let suite = "com.oddurs.zipboy.updatertests.\(UUID().uuidString)"
        updater.defaults = UserDefaults(suiteName: suite)!
        updater.settings = Settings(defaults: UserDefaults(suiteName: suite)!)
        updater.localVersion = "0.4.0"
        let base = "https://github.com/oddurs/zipboy/releases/download/v\(latest)"
        let feed = Data(
            #"""
            {"tag_name": "v\#(latest)", "html_url": "https://github.com/oddurs/zipboy/releases/tag/v\#(latest)",
             "prerelease": false, "assets": [
               {"name": "Zipboy-\#(latest).dmg", "browser_download_url": "\#(base)/Zipboy-\#(latest).dmg"},
               {"name": "Zipboy-\#(latest).dmg.sha256", "browser_download_url": "\#(base)/Zipboy-\#(latest).dmg.sha256"}]}
            """#.utf8)
        let digest = sum ?? SHA256.hash(data: disk).map { String(format: "%02x", $0) }.joined()
        updater.fetch = { url in
            switch url.pathExtension {
            case "dmg": disk
            case "sha256": Data("\(digest)  Zipboy-\(latest).dmg\n".utf8)
            default: feed
            }
        }
        return updater
    }

    @Test func offersANewerReleaseOnceADay() async {
        let updater = updater(latest: "0.4.1")
        let now = Date()
        guard case .offer(let release) = await updater.check(manual: false, now: now) else {
            Issue.record("no offer")
            return
        }
        #expect(release.version == "0.4.1")
        // Not again within the day, nor the same version on a later day.
        #expect(await updater.check(manual: false, now: now.addingTimeInterval(3_600)) == .quiet)
        #expect(await updater.check(manual: false, now: now.addingTimeInterval(90_000)) == .quiet)
        // Asked for, it always answers.
        #expect(await updater.check(manual: true, now: now) == .offer(release))
    }

    @Test func saysUpToDateOnlyWhenAsked() async {
        let updater = updater(latest: "0.4.0")
        #expect(await updater.check(manual: false) == .quiet)
        #expect(await updater.check(manual: true) == .upToDate)
    }

    @Test func turnedOffItStaysQuietUntilAsked() async {
        let updater = updater(latest: "0.4.1")
        updater.settings.checksForUpdates = false
        #expect(await updater.check(manual: false) == .quiet)
        #expect(await updater.check(manual: true) != .quiet)
    }

    @Test func aDownloadThatDoesntMatchIsRefused() async throws {
        let good = updater(latest: "0.4.1")
        guard case .offer(let release) = await good.check(manual: true) else { return }
        let disk = try await good.download(release)
        #expect(try Data(contentsOf: disk) == Data("image".utf8))

        let tampered = updater(latest: "0.4.1", sum: String(repeating: "0", count: 64))
        await #expect(throws: Updater.Failure.self) { try await tampered.download(release) }
        #expect(!FileManager.default.fileExists(atPath: disk.path))
    }
}

/// An error's alert offers the next step as a button.
@MainActor
@Suite struct ErrorRecoveryTests {
    @Test func aPermissionErrorOffersDuplicateAndAFullDiskOffersStorage() throws {
        let doc = ArchiveDocument()
        defer { doc.close() }
        let denied = doc.willPresentError(CocoaError(.fileWriteNoPermission)) as NSError
        #expect(denied.localizedRecoveryOptions == ["Duplicate…", "Cancel"])
        #expect(denied.recoveryAttempter is ErrorRecovery)
        let full = doc.willPresentError(POSIXError(.ENOSPC)) as NSError
        #expect(full.localizedRecoveryOptions == ["Open Storage Settings", "Cancel"])
        // Nothing to do about a wrong password but try again, so no button.
        #expect((doc.willPresentError(ArchiveError.wrongPassword) as NSError).localizedRecoveryOptions == nil)
    }

    @Test func onlyTheFirstButtonRecovers() {
        var ran = 0
        let recovery = ErrorRecovery(.duplicate) { ran += 1 }
        #expect(!recovery.attemptRecovery(fromError: CocoaError(.fileWriteNoPermission), optionIndex: 1))
        #expect(ran == 0)
        #expect(recovery.attemptRecovery(fromError: CocoaError(.fileWriteNoPermission), optionIndex: 0))
        #expect(ran == 1)
    }
}

/// Quarantine marks from downloaded archives survive every exit from the app and pass into nested archives.
@MainActor
@Suite(.serialized) struct QuarantineTests {
    let dir: URL
    let attr = "com.apple.quarantine"
    let eventID = "98765432-1234-1234-1234-ABCDEF012345"
    var mark: Data { Data("0081;672c0000;Safari;\(eventID)".utf8) }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyQuarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func quarantine(on url: URL) -> Data? {
        let length = getxattr(url.path, attr, nil, 0, 0, XATTR_NOFOLLOW)
        guard length >= 0 else { return nil }
        if length == 0 { return Data() }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes {
            getxattr(url.path, attr, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        return read >= 0 ? Data(data.prefix(read)) : nil
    }

    /// Checks `com.apple.quarantine` carries this archive's quarantine event ID, whether written raw
    /// by `setxattr` or canonicalized by `copyfile(3)` during an extract or drag-out copy.
    func isQuarantined(_ url: URL) -> Bool {
        guard let raw = quarantine(on: url), let text = String(data: raw, encoding: .utf8) else { return false }
        return text.contains(eventID)
    }

    func markQuarantine(on url: URL) {
        let bytes = mark
        let rc = bytes.withUnsafeBytes {
            setxattr(url.path, attr, $0.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        #expect(rc == 0)
    }

    func open(_ url: URL) async throws -> (ArchiveDocument, BrowserViewController) {
        let document = ArchiveDocument()
        document.fileURL = url
        document.fileType = ArchiveDocument.zipType
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? ArchiveWindowController)
        controller.browser.loadViewIfNeeded()
        controller.browser.revealFiles = { _ in }
        try document.read(from: url, ofType: ArchiveDocument.zipType)
        for _ in 0..<500 where document.loading != nil || document.tree == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(document.loading == nil)
        controller.browser.reload()
        return (document, controller.browser)
    }

    @Test func quarantineSurvivesEveryExitAndReachesNestedArchives() async throws {
        // Build an unmarked Inner.zip, put it alongside hello.txt in Outer.zip, and mark only Outer.zip.
        let innerSrc = dir.appendingPathComponent("inner-src")
        try FileManager.default.createDirectory(
            at: innerSrc.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: innerSrc.appendingPathComponent("nested/tool"))
        try Data("notes".utf8).write(to: innerSrc.appendingPathComponent("notes.txt"))
        let outerSrc = dir.appendingPathComponent("outer-src")
        try FileManager.default.createDirectory(at: outerSrc, withIntermediateDirectories: true)
        try Archive.writeZip(from: innerSrc, to: outerSrc.appendingPathComponent("Inner.zip"))
        try Data("hello".utf8).write(to: outerSrc.appendingPathComponent("hello.txt"))

        let archiveFolder = dir.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        let outerZip = archiveFolder.appendingPathComponent("Outer.zip")
        try Archive.writeZip(from: outerSrc, to: outerZip)
        markQuarantine(on: outerZip)

        let savedDestination = Settings.shared.extractDestination
        let savedWrap = Settings.shared.wrapExtractedFiles
        Settings.shared.extractDestination = .archiveFolder
        Settings.shared.wrapExtractedFiles = .whenMultipleItems
        defer {
            Settings.shared.extractDestination = savedDestination
            Settings.shared.wrapExtractedFiles = savedWrap
        }

        let (outerDoc, browser) = try await open(outerZip)
        defer { outerDoc.close() }

        // 1. Extract (beside the archive, wrapped because Outer.zip has two top-level items).
        browser.outline.deselectAll(nil)
        browser.extract(nil)
        for _ in 0..<500
        where !outerDoc.tasks.isEmpty
            || !FileManager.default.fileExists(
                atPath: archiveFolder.appendingPathComponent("Outer/hello.txt").path)
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        let wrappedExtract = archiveFolder.appendingPathComponent("Outer")
        #expect(isQuarantined(wrappedExtract))
        #expect(isQuarantined(wrappedExtract.appendingPathComponent("hello.txt")))
        #expect(isQuarantined(wrappedExtract.appendingPathComponent("Inner.zip")))

        // 2. Extract To… (both a chosen item and the whole archive).
        let extractOneDir = dir.appendingPathComponent("extract-to-one")
        try FileManager.default.createDirectory(at: extractOneDir, withIntermediateDirectories: true)
        let helloNode = try #require(outerDoc.tree?.find("hello.txt"))
        await browser.extract(into: extractOneDir, items: [helloNode])?.value
        #expect(isQuarantined(extractOneDir.appendingPathComponent("hello.txt")))

        let extractAllDir = dir.appendingPathComponent("extract-to-all")
        try FileManager.default.createDirectory(at: extractAllDir, withIntermediateDirectories: true)
        await browser.extract(into: extractAllDir, items: [])?.value
        #expect(isQuarantined(extractAllDir.appendingPathComponent("Outer")))
        #expect(isQuarantined(extractAllDir.appendingPathComponent("Outer/hello.txt")))

        // 3. Extract Here service.
        let serviceDir = dir.appendingPathComponent("service-out")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        let serviceResults = try AppDelegate.extractArchives([outerZip], into: serviceDir)
        #expect(serviceResults.map(\.path) == [serviceDir.appendingPathComponent("Outer").path])
        #expect(isQuarantined(serviceDir.appendingPathComponent("Outer")))
        #expect(isQuarantined(serviceDir.appendingPathComponent("Outer/hello.txt")))
        #expect(isQuarantined(serviceDir.appendingPathComponent("Outer/Inner.zip")))

        // 4. AppleScript `extract`.
        let scriptDir = dir.appendingPathComponent("script-out")
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        let scriptResults = try Scripting.extract(outerZip, to: scriptDir)
        #expect(scriptResults.map(\.path) == [scriptDir.appendingPathComponent("Outer").path])
        #expect(isQuarantined(scriptDir.appendingPathComponent("Outer")))
        #expect(isQuarantined(scriptDir.appendingPathComponent("Outer/hello.txt")))

        // 5. Opening a file from the list (and dragging out via file promise).
        var opened: [URL] = []
        browser.openFile = { opened.append($0) }
        browser.select(["hello.txt"])
        browser.openItems(nil)
        #expect(opened.count == 1)
        #expect(isQuarantined(try #require(opened.first)))

        let promised = dir.appendingPathComponent("promised-hello.txt")
        let provider = browser.filePromiseProvider(for: helloNode)
        var promiseError: Error?
        browser.filePromiseProvider(provider, writePromiseTo: promised) { promiseError = $0 }
        #expect(promiseError == nil)
        #expect(isQuarantined(promised))

        // 6. Nested archive opened from the marked archive passes the mark to everything it unpacks.
        let innerURL = try #require(outerDoc.tree?.find("Inner.zip")?.url)
        #expect(isQuarantined(innerURL))
        let (innerDoc, innerBrowser) = try await open(innerURL)
        innerDoc.parentDocument = outerDoc
        defer { innerDoc.close() }
        _ = try await innerDoc.materialize(["nested", "nested/tool", "notes.txt"])
        for path in ["nested", "nested/tool", "notes.txt"] {
            let unpacked = try #require(innerDoc.tree?.find(path)?.url)
            #expect(isQuarantined(unpacked), "\(path)")
        }
        let nestedExtractDir = dir.appendingPathComponent("nested-extract")
        try FileManager.default.createDirectory(at: nestedExtractDir, withIntermediateDirectories: true)
        await innerBrowser.extract(into: nestedExtractDir, items: [])?.value
        #expect(isQuarantined(nestedExtractDir.appendingPathComponent("Inner")))
        #expect(isQuarantined(nestedExtractDir.appendingPathComponent("Inner/nested/tool")))
    }

    @Test func catalogBrowsingListsHundredThousandEntriesUnderOneSecondAndWritesNothingUntilUsed() async throws {
        let fm = FileManager.default
        func appendLE<each T: FixedWidthInteger>(_ data: inout Data, _ values: repeat each T) {
            repeat data.append(contentsOf: Swift.withUnsafeBytes(of: (each values).littleEndian, Array.init))
        }

        // 1. Sorting, search, and folder sizes work before anything is unpacked, and opening writes
        // nothing under $TMPDIR/Zipboy until an entry is used.
        let sampleSrc = dir.appendingPathComponent("cat-browse-src")
        try fm.createDirectory(at: sampleSrc.appendingPathComponent("docs/guides"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sampleSrc.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 120).write(to: sampleSrc.appendingPathComponent("docs/guides/intro.md"))
        try Data(repeating: 0x62, count: 400).write(to: sampleSrc.appendingPathComponent("docs/api.pdf"))
        try Data(repeating: 0x63, count: 80).write(to: sampleSrc.appendingPathComponent("src/main.swift"))
        try Data(repeating: 0x64, count: 30).write(to: sampleSrc.appendingPathComponent("README.txt"))
        try Data(repeating: 0x65, count: 10).write(to: sampleSrc.appendingPathComponent(".hidden"))
        let sampleZip = dir.appendingPathComponent("SampleCatalog.zip")
        try Archive.writeZip(from: sampleSrc, to: sampleZip)

        let (doc, browser) = try await open(sampleZip)
        defer { doc.close() }

        let ws = try #require(doc.workspace)
        #expect(!ws.isCreatedOnDisk)
        #expect(!fm.fileExists(atPath: ws.folder.path))
        #expect(!fm.fileExists(atPath: ws.contents.path))

        let tree = try #require(doc.tree)
        #expect(tree.size == 640)
        #expect(tree.find("docs")?.size == 520)
        #expect(tree.find("docs/guides")?.size == 120)
        #expect(tree.find("src")?.size == 80)

        for key in [Node.SortKey.name, .size, .modified, .kind] {
            tree.sort(by: key, ascending: true)
            tree.sort(by: key, ascending: false)
        }
        tree.sort(by: .size, ascending: false, foldersFirst: false)
        #expect(tree.children.map(\.name) == ["docs", "src", "README.txt", ".hidden"])

        let searched = try #require(tree.filtered("intro"))
        #expect(searched.find("docs/guides/intro.md") != nil)
        #expect(searched.find("src/main.swift") == nil)
        let withoutHidden = try #require(tree.filtered("", showHiddenFiles: false))
        #expect(withoutHidden.find(".hidden") == nil)
        #expect(!ws.isCreatedOnDisk)
        #expect(!fm.fileExists(atPath: ws.folder.path))

        // Materializing one entry creates the workspace and unpacks only that entry.
        _ = browser
        let materializedURLs = try await doc.materialize(["docs/guides/intro.md"])
        #expect(materializedURLs == [ws.url("docs/guides/intro.md")])
        #expect(ws.isCreatedOnDisk)
        #expect(fm.fileExists(atPath: ws.url("docs/guides/intro.md").path))
        #expect(!fm.fileExists(atPath: ws.url("src/main.swift").path))
        #expect(!doc.isDocumentEdited)

        // 2. A 100,000-entry ZIP lists in under a second without unpacking.
        let zip100k = dir.appendingPathComponent("hundred-thousand.zip")
        do {
            let count = 100_000
            let dosDate: UInt16 = (46 << 9) | (11 << 5) | 7
            let dosTime: UInt16 = (12 << 11)
            let payload = Data("0123456789".utf8)
            let exactCRC: UInt32 = 0xA684_C7C6
            var local = Data(capacity: count * 62)
            var central = Data(capacity: count * 70)
            for idx in 0..<count {
                let name = Data("dir\(idx % 100)/file-\(idx).txt".utf8)
                let offset = UInt32(local.count)
                appendLE(&local, UInt32(0x0403_4b50), UInt16(20), UInt16(1 << 11), UInt16(0), dosTime, dosDate)
                appendLE(&local, exactCRC, UInt32(10), UInt32(10), UInt16(name.count), UInt16(0))
                local.append(name)
                local.append(payload)

                appendLE(
                    &central, UInt32(0x0201_4b50), UInt16(0x031E), UInt16(20), UInt16(1 << 11), UInt16(0), dosTime,
                    dosDate)
                appendLE(&central, exactCRC, UInt32(10), UInt32(10), UInt16(name.count), UInt16(0), UInt16(0))
                appendLE(&central, UInt16(0), UInt16(0), UInt32(0o100644) << 16, offset)
                central.append(name)
            }
            let cdOffset = UInt64(local.count)
            let cdSize = UInt64(central.count)
            let z64Offset = cdOffset + cdSize
            var tail = Data()
            appendLE(&tail, UInt32(0x0606_4b50), UInt64(44), UInt16(0x032D), UInt16(45), UInt32(0), UInt32(0))
            appendLE(&tail, UInt64(count), UInt64(count), cdSize, cdOffset)
            appendLE(&tail, UInt32(0x0706_4b50), UInt32(0), z64Offset, UInt32(1))
            appendLE(
                &tail, UInt32(0x0605_4b50), UInt16(0), UInt16(0), UInt16(0xFFFF), UInt16(0xFFFF), UInt32(cdSize),
                UInt32(cdOffset), UInt16(0))
            fm.createFile(atPath: zip100k.path, contents: nil)
            let out = try FileHandle(forWritingTo: zip100k)
            try out.write(contentsOf: local)
            try out.write(contentsOf: central)
            try out.write(contentsOf: tail)
            try out.close()
        }

        let clock = ContinuousClock()
        let start = clock.now
        let catalog = try ZipCatalog.read(from: zip100k)
        let bigTree = Node.fromCatalog(catalog, workspaceRoot: dir)
        let elapsed = clock.now - start

        #expect(catalog.entries.count == 100_000)
        #expect(bigTree.children.count == 100)
        #expect(bigTree.size == 1_000_000)
        #expect(bigTree.find("dir0")?.size == 10_000)
        #expect(elapsed < .seconds(1), "100,000-entry catalog listing took \(elapsed)")
    }

    @Test func onDemandMaterializationPreviewsUnderTwoHundredMillisecondsCoalescesAndCountsUnchanged() async throws {
        let fm = FileManager.default
        let src = dir.appendingPathComponent("mat-src")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        let previewData = Data(repeating: 0x41, count: 1 << 20)
        let coalesceData = Data((0..<(2 << 20)).map { UInt8(($0 * 17) & 0xff) })
        try previewData.write(to: src.appendingPathComponent("preview.txt"))
        try coalesceData.write(to: src.appendingPathComponent("coalesce.bin"))
        try Data("open-payload".utf8).write(to: src.appendingPathComponent("open-me.txt"))
        try Data("open-with-payload".utf8).write(to: src.appendingPathComponent("open-with.txt"))
        try Data("copy-payload".utf8).write(to: src.appendingPathComponent("copy-me.txt"))
        try Data("share-payload".utf8).write(to: src.appendingPathComponent("share-me.txt"))
        try Data("extract-payload".utf8).write(to: src.appendingPathComponent("extract-me.txt"))

        let zip = dir.appendingPathComponent("OnDemand.zip")
        try Archive.writeZip(from: src, to: zip)

        let (doc, browser) = try await open(zip)
        defer { doc.close() }
        let wc = try #require(doc.windowControllers.first as? ArchiveWindowController)
        let ws = try #require(doc.workspace)
        #expect(!ws.isCreatedOnDisk)

        // 1. Selecting a file under 10 MB shows its preview within 200 ms.
        browser.select(["preview.txt"])
        #expect(!wc.preview.spinner.isHidden)
        await wc.preview.previewTask?.value
        let previewElapsed = try #require(wc.preview.lastMaterializationElapsed)
        #expect((wc.preview.quickLook.previewItem as? NSURL) as URL? == ws.url("preview.txt"))
        #expect(wc.preview.spinner.isHidden)
        #expect(fm.fileExists(atPath: ws.url("preview.txt").path))
        #expect(previewElapsed < .milliseconds(200), "Preview materialization took \(previewElapsed)")

        // 2. Two concurrent requests for the same entry unpack it once.
        let req1 = Task { try await doc.materialize(["coalesce.bin"]) }
        let req2 = Task { try await doc.materialize(["coalesce.bin"]) }
        let (urls1, urls2) = try await (req1.value, req2.value)
        #expect(urls1 == [ws.url("coalesce.bin")])
        #expect(urls2 == [ws.url("coalesce.bin")])
        #expect(doc.materializationCounts["coalesce.bin"] == 1)
        #expect(try Data(contentsOf: ws.url("coalesce.bin")) == coalesceData)

        // 3. Open, Open With, Copy, Share, and Extract all materialize first.
        var openedURLs: [URL] = []
        browser.openFile = { openedURLs.append($0) }
        browser.select(["open-me.txt"])
        browser.openItems(nil)
        #expect(openedURLs == [ws.url("open-me.txt")])
        #expect(try Data(contentsOf: ws.url("open-me.txt")) == Data("open-payload".utf8))

        var openedWithPairs: [(urls: [URL], app: URL)] = []
        browser.openWithApp = { urls, app in openedWithPairs.append((urls, app)) }
        let fakeApp = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        browser.open(file: ws.url("open-with.txt"), withApplicationAt: fakeApp)
        #expect(openedWithPairs.count == 1)
        #expect(openedWithPairs.first?.urls == [ws.url("open-with.txt")])
        #expect(try Data(contentsOf: ws.url("open-with.txt")) == Data("open-with-payload".utf8))

        browser.select(["copy-me.txt"])
        browser.copy(nil)
        #expect(try Data(contentsOf: ws.url("copy-me.txt")) == Data("copy-payload".utf8))

        browser.select(["share-me.txt"])
        let shared = wc.items(for: NSSharingServicePickerToolbarItem(itemIdentifier: .share)) as? [URL]
        #expect(shared == [ws.url("share-me.txt")])
        #expect(try Data(contentsOf: ws.url("share-me.txt")) == Data("share-payload".utf8))

        let extractOut = dir.appendingPathComponent("mat-extract-out")
        try fm.createDirectory(at: extractOut, withIntermediateDirectories: true)
        let extractNode = try #require(doc.tree?.find("extract-me.txt"))
        await browser.extract(into: extractOut, items: [extractNode])?.value
        #expect(
            try Data(contentsOf: extractOut.appendingPathComponent("extract-me.txt")) == Data("extract-payload".utf8))

        // 4. Materialized files count as unchanged for saving.
        #expect(!doc.isDocumentEdited)
        for path in [
            "preview.txt", "coalesce.bin", "open-me.txt", "open-with.txt", "copy-me.txt", "share-me.txt",
            "extract-me.txt",
        ] {
            #expect(doc.verbatimEntry(forPath: path) != nil, "\(path)")
        }
    }
}
