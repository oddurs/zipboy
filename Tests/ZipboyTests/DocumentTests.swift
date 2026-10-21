import AppKit
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
}

/// The save path: snapshots, autosaves cancelled by edits, and encryption.
@MainActor
@Suite struct SaveTests {
    let dir: URL

    init() throws {
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
}
