import AppKit
import CryptoKit
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
            "rar", "7z", "tar", "tgz", "tbz2", "txz", "tlz", "tzst", "taz", "cpgz", "xar", "cab", "lha", "deb", "zipx",
        ] {
            let type = try controller.typeForContents(of: URL(fileURLWithPath: "/tmp/sample.\(ext)"))
            #expect(type == "public.archive", "\(ext)")
        }
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
        var calls = 0
        // Stops partway through the second file, after the first is in place.
        let files = (0..<3).map { source.appendingPathComponent("part \($0).bin") }
        let watcher = progress.observe(\.completedUnitCount) { progress, _ in
            calls += 1
            if progress.completedUnitCount > (2 << 20) { progress.cancel() }
        }
        defer { watcher.invalidate() }
        #expect(throws: ArchiveError.cancelled) {
            _ = try BrowserViewController.copy(files, into: out, progress: progress, clone: false)
        }
        #expect(calls > 0)
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
