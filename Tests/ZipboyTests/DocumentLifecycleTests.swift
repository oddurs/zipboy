import AppKit
import Foundation
import Security
import Testing
import ZipboyKit

@testable import Zipboy

/// What happens to a document's edits, file, and password when it re-reads names, is saved, moves, or
/// is closed with a nested archive open.
@MainActor
@Suite struct DocumentLifecycleTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyLifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func zip(_ files: [String: Data], to zip: URL) throws {
        let source = dir.appendingPathComponent("source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: source.appendingPathComponent(name)) }
        try Archive.writeZip(from: source, to: zip)
    }

    func open(_ url: URL, type: String = ArchiveDocument.zipType) async throws -> ArchiveDocument {
        let document = ArchiveDocument()
        document.fileURL = url
        document.fileType = type
        try document.read(from: url, ofType: type)
        try await settle(document)
        return document
    }

    func settle(_ document: ArchiveDocument) async throws {
        for _ in 0..<500 where document.loading != nil || document.tree == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(document.loading == nil)
    }

    /// One undo group, as one event would make in the app. NSDocument counts the change on a later
    /// turn of the main queue, so this waits for it.
    func edit(_ document: ArchiveDocument, _ body: () throws -> Void) async throws {
        let undo = try #require(document.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try body()
        undo.endUndoGrouping()
        for _ in 0..<100 where !document.isDocumentEdited { try await Task.sleep(for: .milliseconds(10)) }
        #expect(document.isDocumentEdited)
    }

    func names(in zip: URL) throws -> [String] {
        let root = dir.appendingPathComponent("read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Archive.extract(zip, into: root)
        return try Archive.contents(of: root)
    }

    // MARK: Re-reading names

    @Test func reReadingNamesWithUnsavedEditsAsksFirst() async throws {
        let url = dir.appendingPathComponent("Names.zip")
        try zip(["a.txt": Data("a".utf8)], to: url)
        let document = try await open(url)
        defer { document.close() }
        try await edit(document) { _ = try document.newFolder(in: "") }

        var asked = 0
        await document.reload(withEncoding: .cp437) {
            asked += 1
            return false
        }
        #expect(asked == 1)
        #expect(document.tree?.find("untitled folder") != nil)
        #expect(document.encoding == .auto)
        #expect(document.undoManager?.canUndo == true)

        await document.reload(withEncoding: .cp437) {
            asked += 1
            return true
        }
        #expect(asked == 2)
        #expect(document.tree?.find("untitled folder") == nil)
        #expect(document.encoding == .cp437)
        #expect(!document.isDocumentEdited)
    }

    @Test func anImportSavedAsAZipKeepsItsFileWhenNamesAreReRead() async throws {
        let fixture = BundleTests.root.appendingPathComponent("Tests/ZipboyKitTests/Fixtures/container.rar")
        let rar = dir.appendingPathComponent("container.rar")
        try FileManager.default.copyItem(at: fixture, to: rar)
        let document = try await open(rar, type: "com.rarlab.rar-archive")
        defer { document.close() }

        let saved = dir.appendingPathComponent("container.zip")
        let outcome = SaveTests.Outcome()
        document.save(to: saved, ofType: ArchiveDocument.zipType, for: .saveAsOperation) { error in
            outcome.error = error
            outcome.finished = true
        }
        for _ in 0..<3000 where !outcome.finished { try await Task.sleep(for: .milliseconds(10)) }
        #expect(outcome.finished && outcome.error == nil)
        #expect(document.fileURL?.standardizedFileURL == saved.standardizedFileURL)
        #expect(document.importedFrom == nil)

        await document.reload(withEncoding: .auto) {
            Issue.record("Asked to discard changes when there were none")
            return false
        }
        // Re-read as an import, it lost its file URL and the next save asked where to put a new one.
        #expect(document.fileURL?.standardizedFileURL == saved.standardizedFileURL)
        #expect(document.importedFrom == nil)
        #expect(document.tree?.children.map(\.name) == ["container"])
    }

    // MARK: Keychain

    /// A service of the test's own, so the login Keychain's real items are never read or touched.
    func throwawayService() -> String { "com.oddurs.zipboy.tests.\(UUID().uuidString)" }

    /// Removes every item under `service`, including any a failing test left behind under a stale key.
    func removeAll(service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        while SecItemDelete(query as CFDictionary) == errSecSuccess {}
    }

    @Test func aRememberedPasswordSurvivesSavingInPlace() throws {
        let service = throwawayService()
        defer { removeAll(service: service) }
        let url = dir.appendingPathComponent("Locked.zip")
        try Data("before".utf8).write(to: url)
        try Keychain.setPassword("s3cr3t", for: url, service: service)

        // NSDocument saves by writing a new file and renaming it over the old one, as this does.
        let staged = dir.appendingPathComponent("staged.zip")
        try Data("after".utf8).write(to: staged)
        #expect(rename(staged.path, url.path) == 0)

        #expect(Keychain.password(for: url, service: service) == "s3cr3t")
    }

    @Test func aRememberedPasswordMovesWithItsArchive() async throws {
        let service = throwawayService()
        defer { removeAll(service: service) }
        let url = dir.appendingPathComponent("Before.zip")
        try zip(["a.txt": Data("a".utf8)], to: url)
        let document = try await open(url)
        defer { document.close() }
        document.keychainService = service
        document.setPassword("s3cr3t")
        try Keychain.setPassword("s3cr3t", for: url, service: service)

        // Renamed in the title bar, or File > Move To.
        let renamed = dir.appendingPathComponent("Renamed.zip")
        let outcome = SaveTests.Outcome()
        document.move(to: renamed) { error in
            outcome.error = error
            outcome.finished = true
        }
        for _ in 0..<500 where !outcome.finished { try await Task.sleep(for: .milliseconds(10)) }
        #expect(outcome.finished && outcome.error == nil)
        #expect(Keychain.password(for: renamed, service: service) == "s3cr3t")
        #expect(Keychain.password(for: url, service: service) == nil)

        // Moved in Finder, which the document hears of as a file presenter.
        let elsewhere = dir.appendingPathComponent("Elsewhere.zip")
        try FileManager.default.moveItem(at: renamed, to: elsewhere)
        document.presentedItemDidMove(to: elsewhere)
        for _ in 0..<100 where Keychain.password(for: elsewhere, service: service) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(Keychain.password(for: elsewhere, service: service) == "s3cr3t")
        #expect(Keychain.password(for: renamed, service: service) == nil)
    }

    // MARK: Nested archives

    /// Records AppKit's answer to `canClose(withDelegate:shouldClose:contextInfo:)`.
    final class CloseAnswer: NSObject {
        var shouldClose: Bool?

        @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            self.shouldClose = shouldClose
        }
    }

    @Test func closingAParentSavesTheNestedArchiveOpenFromItFirst() async throws {
        let inner = dir.appendingPathComponent("nested.zip")
        try zip(["inner.txt": Data("inner".utf8)], to: inner)
        let outerSource = dir.appendingPathComponent("outer")
        try FileManager.default.createDirectory(at: outerSource, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: inner, to: outerSource.appendingPathComponent("nested.zip"))
        let outer = dir.appendingPathComponent("Outer.zip")
        try Archive.writeZip(from: outerSource, to: outer)

        let parent = try await open(outer)
        let nestedURL = try #require(parent.workspace?.contents.appendingPathComponent("nested.zip"))
        let child = try await open(nestedURL)
        child.parentDocument = parent
        try await edit(child) { _ = try child.newFolder(in: "") }

        let answer = CloseAnswer()
        parent.canClose(
            withDelegate: answer, shouldClose: #selector(CloseAnswer.document(_:shouldClose:contextInfo:)),
            contextInfo: nil)
        for _ in 0..<3000 where answer.shouldClose == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(answer.shouldClose == true)
        parent.close()
        child.close()

        let unpacked = dir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        _ = try Archive.extract(outer, into: unpacked)
        #expect(try names(in: unpacked.appendingPathComponent("nested.zip")) == ["inner.txt", "untitled folder"])
    }
}
