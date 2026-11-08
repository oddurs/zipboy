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

    // MARK: Trash after extract

    @Test func moveArchiveToTrashAfterExtractHonorsSettingFailurePartialAndUnsavedEdits() async throws {
        let suiteName = "com.oddurs.zipboy.trash.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = Settings(defaults: defaults)
        settings.afterExtract = .moveToTrash
        settings.revealExtractedInFinder = false

        let trashFolder = dir.appendingPathComponent("SimulatedTrash")
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        nonisolated(unsafe) var trashed: [URL] = []
        settings.trashItem = { url in
            trashed.append(url)
            let dest = trashFolder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: dest)
        }

        // 1. Successful Extract Here moves the archive to the Trash.
        let serviceZip = dir.appendingPathComponent("ServiceExtract.zip")
        try zip(["hello.txt": Data("hello".utf8)], to: serviceZip)
        let serviceOutDir = dir.appendingPathComponent("service-out")
        try FileManager.default.createDirectory(at: serviceOutDir, withIntermediateDirectories: true)
        let serviceOutputs = try AppDelegate.extractArchives(
            [serviceZip], into: serviceOutDir, settings: settings)
        #expect(serviceOutputs.count == 1)
        #expect(!FileManager.default.fileExists(atPath: serviceZip.path))
        #expect(trashed.map(\.standardizedFileURL) == [serviceZip.standardizedFileURL])

        // 2. A failed extract leaves the archive where it was.
        trashed.removeAll()
        let brokenZip = dir.appendingPathComponent("Broken.zip")
        try Data("not a valid zip archive".utf8).write(to: brokenZip)
        #expect(throws: Error.self) {
            _ = try AppDelegate.extractArchives([brokenZip], into: serviceOutDir, settings: settings)
        }
        #expect(FileManager.default.fileExists(atPath: brokenZip.path))
        #expect(trashed.isEmpty)

        // 3. Extracting only some items from a window never trashes the archive.
        let windowZip = dir.appendingPathComponent("WindowArchive.zip")
        try zip(["one.txt": Data("1".utf8), "two.txt": Data("2".utf8)], to: windowZip)
        let doc = try await open(windowZip)
        doc.makeWindowControllers()
        let browser = try #require((doc.windowControllers.first as? ArchiveWindowController)?.browser)
        browser.settings = settings

        let partialDir = dir.appendingPathComponent("partial-out")
        try FileManager.default.createDirectory(at: partialDir, withIntermediateDirectories: true)
        let oneNode = try #require(doc.tree?.find("one.txt"))
        await browser.extract(into: partialDir, items: [oneNode])?.value
        #expect(FileManager.default.fileExists(atPath: windowZip.path))
        #expect(trashed.isEmpty)
        #expect(!doc.windowControllers.isEmpty)

        // 4. An archive with unsaved edits is never trashed, and its window stays open.
        try await edit(doc) { _ = try doc.newFolder(in: "") }
        let editedOutDir = dir.appendingPathComponent("edited-out")
        try FileManager.default.createDirectory(at: editedOutDir, withIntermediateDirectories: true)
        await browser.extract(into: editedOutDir, items: [])?.value
        #expect(FileManager.default.fileExists(atPath: windowZip.path))
        #expect(trashed.isEmpty)
        #expect(!doc.windowControllers.isEmpty)

        // 5. Once edits are cleared, extracting the whole archive moves it to the Trash and closes its window.
        doc.updateChangeCount(.changeCleared)
        #expect(!doc.isDocumentEdited)
        let wholeOutDir = dir.appendingPathComponent("whole-out")
        try FileManager.default.createDirectory(at: wholeOutDir, withIntermediateDirectories: true)
        await browser.extract(into: wholeOutDir, items: [])?.value
        #expect(!FileManager.default.fileExists(atPath: windowZip.path))
        #expect(trashed.map(\.standardizedFileURL) == [windowZip.standardizedFileURL])
    }

    // MARK: Batch extract

    @Test func batchExtractRunsFiveArchivesAsOneTaskCarriesOnPastFailureAndStopsNestedAtDepthLimit() throws {
        let suiteName = "com.oddurs.zipboy.batch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = Settings(defaults: defaults)
        settings.revealExtractedInFinder = false

        // 1. Five archives run as one LongTask with one progress bar and one finish notice.
        var fiveArchives: [URL] = []
        for idx in 1...5 {
            let url = dir.appendingPathComponent("batch-\(idx).zip")
            try zip(["item-\(idx).txt": Data("content-\(idx)".utf8)], to: url)
            fiveArchives.append(url)
        }

        let notifier = RecordingNotifier()
        let watcher = TaskWatcher()
        watcher.notifier = notifier
        watcher.isFrontmost = { false }

        let out1 = dir.appendingPathComponent("batch-out-1")
        try FileManager.default.createDirectory(at: out1, withIntermediateDirectories: true)
        let res1 = AppDelegate.extractBatch(
            fiveArchives,
            into: out1,
            settings: settings,
            watcher: watcher,
            taskStarted: Date().addingTimeInterval(-3)
        )
        #expect(res1.outputs.count == 5)
        #expect(res1.failures.isEmpty)
        #expect(res1.task.progress.totalUnitCount == 500)
        #expect(res1.task.progress.completedUnitCount == 500)
        #expect(res1.task.progress.fractionCompleted == 1.0)
        #expect(notifier.posted.count == 1)
        #expect(notifier.posted.first?.0 == "Extracting 5 archives")
        #expect(notifier.posted.first?.1 == "5 archives")

        // 2. One damaged archive among five doesn't stop the other four, and the summary names it.
        try Data("damaged bytes".utf8).write(to: fiveArchives[2])
        let out2 = dir.appendingPathComponent("batch-out-2")
        try FileManager.default.createDirectory(at: out2, withIntermediateDirectories: true)
        let res2 = AppDelegate.extractBatch(
            fiveArchives,
            into: out2,
            settings: settings,
            watcher: watcher,
            taskStarted: Date().addingTimeInterval(-3)
        )
        #expect(res2.outputs.count == 4)
        #expect(res2.failures.count == 1)
        #expect(res2.failures[0].url.lastPathComponent == "batch-3.zip")
        let summary = try #require(res2.failureSummary)
        #expect(summary.contains("batch-3.zip"))

        // 3. Unpacking nested archives stops at Settings.maxNestedArchiveDepth with an archive holding itself.
        let recursiveZip = dir.appendingPathComponent("self.zip")
        try zip(["bottom.txt": Data("bottom".utf8)], to: recursiveZip)
        for layer in 1...8 {
            let stage = dir.appendingPathComponent("self-stage-\(layer)")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: recursiveZip, to: stage.appendingPathComponent("self.zip"))
            try Data("layer-\(layer)".utf8).write(to: stage.appendingPathComponent("layer.txt"))
            try Archive.writeZip(from: stage, to: recursiveZip)
        }

        settings.unpackNestedArchives = true
        let out3 = dir.appendingPathComponent("batch-out-3")
        try FileManager.default.createDirectory(at: out3, withIntermediateDirectories: true)
        let res3 = AppDelegate.extractBatch([recursiveZip], into: out3, settings: settings)
        #expect(res3.failures.isEmpty)
        let subpaths = try FileManager.default.subpathsOfDirectory(atPath: out3.path)
        #expect(!subpaths.contains { $0.hasSuffix("bottom.txt") })
        #expect(subpaths.contains { $0.hasSuffix("self.zip") })
        let remainingZip = try #require(subpaths.first { $0.hasSuffix("self.zip") })
        let depthComponents = remainingZip.split(separator: "/").filter { $0 == "self" }
        #expect(depthComponents.count == Settings.maxNestedArchiveDepth + 1)
    }

    @Test func splitArchivesOpenReadOnlyAsImportsFromAnyPieceSoAutosaveNeverOverwritesAPiece() async throws {
        let fm = FileManager.default
        let splitFixtureRoot = BundleTests.root.appendingPathComponent("Tests/ZipboyKitTests/Fixtures/split")
        let sets: [(stem: String, pieces: [String])] = [
            ("split-part", ["split-part.part1.rar", "split-part.part2.rar"]),
            ("split-old", ["split-old.rar", "split-old.r00", "split-old.r01"]),
            ("split-zip", ["split-zip.z01", "split-zip.zip"]),
            ("split-7z", ["split-7z.7z.001", "split-7z.7z.002"]),
            ("split-tar", ["split-tar.tar.001", "split-tar.tar.002"]),
        ]

        let controller = DocumentController()
        for set in sets {
            let folder = dir.appendingPathComponent("doc-\(set.stem)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var pieceURLs: [URL] = []
            var originalBytes: [URL: Data] = [:]
            for name in set.pieces {
                let src = splitFixtureRoot.appendingPathComponent(name)
                let dst = folder.appendingPathComponent(name)
                try fm.copyItem(at: src, to: dst)
                pieceURLs.append(dst)
                originalBytes[dst] = try Data(contentsOf: dst)
            }

            // Open from the first piece and from the last piece.
            for pieceURL in [pieceURLs.first!, pieceURLs.last!] {
                let docType = try controller.typeForContents(of: pieceURL)
                #expect(docType == "public.archive", "\(pieceURL.lastPathComponent)")

                let doc = try await open(pieceURL, type: docType)
                defer { doc.close() }

                #expect(doc.fileURL == nil, "\(pieceURL.lastPathComponent) must open as an import with fileURL == nil")
                #expect(doc.importedFrom?.url == pieceURL)
                #expect(doc.suggestedName == set.stem)
                #expect(doc.tree?.find("hello.txt") != nil)
                #expect(doc.tree?.find("dir/world.txt") != nil)

                // Edit the document and confirm none of the split pieces on disk are touched.
                try await edit(doc) { _ = try doc.newFolder(in: "") }
                for (u, expected) in originalBytes {
                    #expect(try Data(contentsOf: u) == expected, "\(u.lastPathComponent) was modified")
                }
            }
        }
    }
}
