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
