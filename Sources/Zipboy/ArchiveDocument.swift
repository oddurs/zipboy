import AppKit
import ZipboyKit
import os

/// An archive unpacked into a workspace. Edits change the workspace and register their undo; saving
/// zips the workspace back up. Every readable format saves as ZIP, the one format worth writing.
@objc(ArchiveDocument)
final class ArchiveDocument: NSDocument {
    nonisolated static let zipType = "public.zip-archive"
    nonisolated private static let logger = Logger(subsystem: "com.oddurs.zipboy", category: "Save")

    struct TrackedFile: Equatable, Sendable {
        let entry: ZipCatalog.Entry
        let identity: FileIdentity
    }

    /// Enough of a workspace file to tell later whether it still holds the bytes an entry was made from.
    struct FileIdentity: Equatable, Sendable {
        let inode: UInt64
        let size: Int64
        let mtimeSec: Int
        let mtimeNsec: Int

        static func of(_ url: URL) -> FileIdentity? {
            var st = stat()
            guard url.withUnsafeFileSystemRepresentation({ $0 != nil && lstat($0!, &st) == 0 }),
                (st.st_mode & S_IFMT) == S_IFREG
            else { return nil }
            return FileIdentity(
                inode: st.st_ino,
                size: st.st_size,
                mtimeSec: st.st_mtimespec.tv_sec,
                mtimeNsec: st.st_mtimespec.tv_nsec
            )
        }

        /// Every file under `root`, by its path there.
        static func all(in root: URL) -> [String: FileIdentity] {
            var result: [String: FileIdentity] = [:]
            for path in (try? Archive.contents(of: root)) ?? [] {
                result[path] = of(root.appendingPathComponent(path))
            }
            return result
        }
    }

    struct SourceSignature: Equatable, Sendable {
        let url: URL
        let inode: UInt64
        let size: Int64
        let mtimeSec: Int
        let mtimeNsec: Int

        static func of(_ url: URL) -> SourceSignature? {
            var st = stat()
            guard url.withUnsafeFileSystemRepresentation({ $0 != nil && lstat($0!, &st) == 0 }) else {
                return nil
            }
            return SourceSignature(
                url: url.standardizedFileURL,
                inode: st.st_ino,
                size: st.st_size,
                mtimeSec: st.st_mtimespec.tv_sec,
                mtimeNsec: st.st_mtimespec.tv_nsec
            )
        }
    }

    private(set) var workspace: Workspace?
    private(set) var tree: Node?
    /// Set when the archive came from a format that can't be written back, such as RAR. Like Pages
    /// with a Word file, it then opens as a new document named after the original, and the original is
    /// never touched.
    private(set) var importedFrom: (url: URL, format: String)?
    /// Kept from opening an encrypted archive, so saving encrypts it again rather than quietly dropping
    /// the protection.
    private(set) var password: String?
    /// Filename encoding used for non-UTF-8 entry names; `.auto` unless overridden in View > Text Encoding.
    private(set) var encoding: TextEncoding = .auto
    /// Parent archive document when this archive was opened from inside another archive.
    weak var parentDocument: ArchiveDocument? {
        didSet {
            oldValue?.nestedDocuments.remove(self)
            parentDocument?.nestedDocuments.add(self)
        }
    }
    /// Archives opened from inside this one. Their files live in this workspace, so they close first.
    private let nestedDocuments = NSHashTable<ArchiveDocument>.weakObjects()
    private static let openDocuments = NSHashTable<ArchiveDocument>.weakObjects()
    /// Where remembered passwords are kept; tests use a service of their own.
    var keychainService = Keychain.defaultService
    /// Original Central Directory catalog and per-inode file provenance for verbatim delta saves.
    private(set) var catalog: ZipCatalog?
    private(set) var trackedByInode: [UInt64: TrackedFile] = [:]
    private(set) var sourceSignature: SourceSignature?
    private(set) var sourceHandle: FileHandle?
    private(set) var sourceQuarantine: Data?
    /// Entries from the source ZIP catalog that have not yet been unpacked onto disk, keyed by their
    /// current archive path.
    private(set) var unmaterialized: [String: ZipCatalog.Entry] = [:]
    private(set) var unmaterializedFolders: [String: Date?] = [:]
    private(set) var unmaterializedDirEntries: [String: ZipCatalog.Entry] = [:]
    private var heldUnmaterialized: [String: [(suffix: String, entry: ZipCatalog.Entry)]] = [:]
    private var heldUnmaterializedFolders: [String: [(suffix: String, modified: Date?, dirEntry: ZipCatalog.Entry?)]] =
        [:]
    private var materializingByPath: [String: Task<URL, Error>] = [:]
    private(set) var materializationCounts: [String: Int] = [:]
    private(set) var lastMaterializationDuration: Duration?

    /// How far unpacking has got, from 0 to 1, or nil when the contents are ready.
    private(set) var loading: Double?
    private var cancelLoading = Cancellation()
    /// Long work under way after loading, such as "Saving… 40%", for the window's subtitle.
    private(set) var activity: String?
    /// Long work under way, newest last: the window shows the newest with a bar and a stop button.
    private(set) var tasks: [LongTask] = []
    /// Says a change out loud for VoiceOver. Each document has its own, so a test hears only its own.
    var announce: (String) -> Void = { Announcer.say($0) }
    /// Receives save fallback log lines so tests can observe when a delta save falls back to a full write.
    var onSaveLog: (@Sendable (String) -> Void)?
    /// Copies clone on APFS, which is instant and reports no progress; tests turn it off to have some.
    var cloneWhenCopying = true
    private var saving: Saving?

    private struct DeltaPlan: Sendable {
        let items: [ZipWriter.Item]
        let sourceSignature: SourceSignature
        let comment: Data
    }

    private struct SaveJob: Sendable {
        let contents: URL
        let password: String?
        let compressionLevel: Settings.CompressionLevel
        let deltaPlan: DeltaPlan?
        let unmaterialized: [String: ZipCatalog.Entry]
        let unmaterializedFolders: [String: Date?]
        let sourceURL: URL?
        let sourceHandle: FileHandle?
        let sourceQuarantine: Data?
        let encoding: TextEncoding
        let onSaveLog: (@Sendable (String) -> Void)?
        let cancellation: Cancellation
    }

    /// The snapshot the background save zips, handed from the main thread to the writing one.
    private let pendingSave = Locked<SaveJob?>(nil)

    private struct Saving {
        let cancellation: Cancellation
        let autosave: Bool
        var shown = false
    }
    private var watcher: FileWatcher?
    /// What the workspace looked like after the last change made here, to tell an outside edit apart.
    private var signature: [String: String] = [:]

    /// The window controller listens here to redraw: the list and all when the contents change, only
    /// the status when the format, password, or activity does.
    var onChange: (() -> Void)?
    var onStatus: (() -> Void)?

    /// Edits save themselves, as in Pages and Preview, with versions to go back to.
    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        if workspace == nil, loading == nil {
            do {
                install(try Workspace(), password: nil, catalog: nil, sourceURL: nil)
            } catch {
                presentError(error)
            }
        }
        addWindowController(ArchiveWindowController(document: self))
    }

    /// Archives opened from inside this one close first, each saving into this workspace or asking, as
    /// closing it would. What they wrote is then in what this one saves, and none is left with a file in
    /// a workspace that's about to be deleted.
    override func canClose(
        withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let nested = nestedDocuments.allObjects.first else {
            return super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        let answer = CloseAnswer { shouldClose in
            guard shouldClose else {
                return self.answer(delegate, shouldCloseSelector, shouldClose: false, contextInfo)
            }
            nested.close()
            self.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        nested.canClose(withDelegate: answer, shouldClose: CloseAnswer.selector, contextInfo: nil)
    }

    /// Calls AppKit's `document:shouldClose:contextInfo:` back, which Swift can't do through `perform`
    /// because of the `BOOL`.
    private func answer(
        _ delegate: Any, _ selector: Selector?, shouldClose: Bool, _ contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let selector, let target = delegate as? NSObject else { return }
        typealias Callback = @convention(c) (NSObject, Selector, NSDocument, ObjCBool, UnsafeMutableRawPointer?) -> Void
        let callback = unsafeBitCast(target.method(for: selector), to: Callback.self)
        callback(target, selector, self, ObjCBool(shouldClose), contextInfo)
    }

    /// Hears a nested document's answer. AppKit doesn't keep the delegate, so it keeps itself until then.
    private final class CloseAnswer: NSObject {
        static let selector = #selector(document(_:shouldClose:contextInfo:))
        private var answered: ((Bool) -> Void)?
        private var keepAlive: CloseAnswer?

        init(_ answered: @escaping (Bool) -> Void) {
            self.answered = answered
            super.init()
            keepAlive = self
        }

        @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            let answered = self.answered
            self.answered = nil
            keepAlive = nil
            answered?(shouldClose)
        }
    }

    override func close() {
        Self.openDocuments.remove(self)
        parentDocument = nil
        cancelLoading.cancel()
        for task in materializingByPath.values { task.cancel() }
        materializingByPath.removeAll()
        watcher?.stop()
        watcher = nil
        try? sourceHandle?.close()
        sourceHandle = nil
        workspace?.discard()
        workspace = nil
        super.close()
    }

    // MARK: Reading and writing

    /// Only notes what to unpack. The window opens straight away and unpacks with a progress bar, so a
    /// large archive never stalls the app, and a password can be asked for in a sheet.
    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        onMain {
            self.cancelLoading.cancel()
            self.cancelLoading = Cancellation()
            self.loading = 0
            self.onChange?()
            // After makeWindowControllers when opening, so the window is there to hold sheets.
            DispatchQueue.main.async { Task { await self.unpack(url, ofType: typeName) } }
        }
    }

    private enum UnpackOutcome: Sendable {
        case catalog(Workspace, ZipCatalog, FileHandle?, Data?)
        case extracted(Workspace, ExtractSummary, ZipCatalog?)
    }

    private func unpack(_ url: URL, ofType typeName: String) async {
        let cancellation = cancelLoading
        let chosenEncoding = encoding
        if !FileManager.default.fileExists(atPath: url.path) {
            let stdURL = url.standardizedFileURL.path
            for doc in Self.openDocuments.allObjects {
                guard let ws = doc.workspace else { continue }
                let prefix = ws.contents.standardizedFileURL.path + "/"
                if stdURL.hasPrefix(prefix) {
                    let relPath = String(stdURL.dropFirst(prefix.count))
                    _ = try? await doc.materialize([relPath])
                    break
                }
            }
        }
        var password = self.password ?? Keychain.password(for: url, service: keychainService)
        var usedSavedKeychain = (self.password == nil && password != nil)
        var rememberEnteredInKeychain = false
        var keychainFailure: Error?
        let isSplit = Archive.isSplitArchive(url)
        let isEditableZip = typeName == Self.zipType && !isSplit
        while true {
            do {
                let outcome = try await Task.detached { [password] () throws -> UnpackOutcome in
                    if isEditableZip, password == nil,
                        let parsed = try? ZipCatalog.read(from: url, encoding: chosenEncoding),
                        !parsed.isEncrypted
                    {
                        let maxEntries = 250_000
                        if parsed.entries.count > maxEntries {
                            throw ArchiveError.suspiciousArchive(
                                "This archive contains more than \(maxEntries.formatted()) items and was stopped to protect against a decompression bomb."
                            )
                        }
                        let workspace = try Workspace(lazy: true)
                        let handle = try? FileHandle(forReadingFrom: url)
                        let quarantine = Archive.quarantine(of: url)
                        return .catalog(workspace, parsed, handle, quarantine)
                    }

                    let workspace = try Workspace()
                    do {
                        let summary = try Archive.extract(
                            url, into: workspace.contents, password: password, encoding: chosenEncoding
                        ) { done in
                            DispatchQueue.main.async { self.progressed(done, cancellation) }
                            return !cancellation.isCancelled
                        }
                        let catalog: ZipCatalog? =
                            if isEditableZip, !summary.encrypted {
                                try? ZipCatalog.read(from: url, encoding: chosenEncoding)
                            } else {
                                nil
                            }
                        return .extracted(workspace, summary, catalog)
                    } catch {
                        workspace.discard()
                        throw error
                    }
                }.value
                switch outcome {
                case .catalog(let workspace, let parsedCatalog, let handle, let quarantine):
                    guard !cancellation.isCancelled else {
                        try? handle?.close()
                        workspace.discard()
                        return
                    }
                    installCatalog(
                        workspace,
                        catalog: parsedCatalog,
                        sourceURL: url,
                        sourceHandle: handle,
                        quarantine: quarantine
                    )
                    return

                case .extracted(let workspace, let summary, let parsedCatalog):
                    guard !cancellation.isCancelled else { return workspace.discard() }
                    if summary.encrypted, rememberEnteredInKeychain, let password {
                        do {
                            try Keychain.setPassword(password, for: url, service: keychainService)
                        } catch {
                            keychainFailure = error
                        }
                    }
                    install(
                        workspace,
                        password: summary.encrypted ? password : nil,
                        catalog: parsedCatalog,
                        sourceURL: isEditableZip ? url : nil
                    )
                    if !isEditableZip {
                        importedFrom = (url, Self.shortName(summary.format))
                        fileURL = nil
                        fileType = Self.zipType
                        suggestedName = Naming.stem(of: url)
                    }
                    // After the contents are in, so the archive opens whether or not the password was kept.
                    if let keychainFailure { reportKeychainFailure(keychainFailure) }
                    return
                }
            } catch let error as ArchiveError where error == .passwordRequired || error == .wrongPassword {
                guard !cancellation.isCancelled else { return }
                if usedSavedKeychain {
                    Keychain.deletePassword(for: url, service: keychainService)
                    usedSavedKeychain = false
                    let entered = await Prompts.password(
                        for: url.lastPathComponent, retry: false, in: windowForSheet)
                    guard let entered else { return close() }
                    password = entered.password
                    rememberEnteredInKeychain = entered.rememberInKeychain
                } else {
                    let entered = await Prompts.password(
                        for: url.lastPathComponent, retry: error == .wrongPassword, in: windowForSheet)
                    guard let entered else { return close() }
                    password = entered.password
                    rememberEnteredInKeychain = entered.rememberInKeychain
                }
            } catch {
                guard !cancellation.isCancelled else { return }
                // The window has nothing to show, so it goes once the error is read.
                let alert = Prompts.makeErrorAlert(for: error, fileName: url.lastPathComponent)
                if let window = windowForSheet {
                    _ = await alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
                return close()
            }
        }
    }

    /// Re-reads the archive from its source file using `newEncoding` for non-UTF-8 entry names. That
    /// unpacks it afresh, losing unsaved changes and the undo stack, so `confirm` is asked first when
    /// there are unsaved changes.
    func reload(withEncoding newEncoding: TextEncoding, confirm: () async -> Bool) async {
        guard canReload else { return }
        if isDocumentEdited {
            // Asked again after the sheet: a save or another reload may have started meanwhile.
            guard await confirm(), canReload else { return }
        }
        guard let sourceURL = source else { return }
        encoding = newEncoding
        let typeName = importedFrom == nil ? Self.zipType : "public.archive"
        cancelLoading.cancel()
        cancelLoading = Cancellation()
        loading = 0
        onChange?()
        await unpack(sourceURL, ofType: typeName)
        // The workspace is what the file holds again, so there is nothing left to save.
        updateChangeCount(.changeCleared)
    }

    /// Not while unpacking, nor while a save is replacing the file that would be read.
    private var canReload: Bool { source != nil && loading == nil && saving == nil }

    @objc func selectEncoding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let chosen = TextEncoding(rawValue: raw)
        else { return }
        Task {
            await reload(withEncoding: chosen) {
                await Prompts.discardChanges(toReadNamesAs: chosen, in: self.windowForSheet)
            }
        }
    }

    /// What a new archive is called until it's saved: after the one thing put in it, as Finder's
    /// Compress names its zip, or plain "Archive".
    var suggestedName: String? {
        didSet {
            windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
            onStatus?()
        }
    }

    override func defaultDraftName() -> String { suggestedName ?? "Archive" }

    override var displayName: String! {
        get {
            let base = (fileURL == nil ? defaultDraftName() : super.displayName) ?? "Archive"
            if let parentName = parentDocument?.displayName, !parentName.isEmpty {
                return "\(base) — \(parentName)"
            }
            return base
        }
        set { super.displayName = newValue }
    }

    /// The empty window from launch, which an opened archive takes the place of, as in TextEdit.
    var isTransient: Bool {
        fileURL == nil && importedFrom == nil && parentDocument == nil && !isDocumentEdited && loading == nil
            && tree?.children.isEmpty != false
    }

    private func progressed(_ done: Double, _ cancellation: Cancellation) {
        guard cancellation === cancelLoading, loading != nil else { return }
        loading = done
        onChange?()
    }

    override func canAsynchronouslyWrite(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
    ) -> Bool { true }

    /// Whatever the archive was read from, what gets written is a ZIP, autosaves included.
    override var autosavingFileType: String? { Self.zipType }

    /// Snapshots the workspace before handing over to the writing thread, so saving a large archive
    /// doesn't hold up the window, and edits made meanwhile wait for the next save.
    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let workspace else { return completionHandler(CocoaError(.fileWriteUnknown)) }
        let canUseDelta: Bool = {
            guard password == nil, catalog != nil, let expectedSig = sourceSignature else { return false }
            if SourceSignature.of(expectedSig.url) != expectedSig {
                Self.logSourceChangedFallback(for: expectedSig.url, notify: onSaveLog)
                return false
            }
            return true
        }()
        if !canUseDelta, !unmaterialized.isEmpty || !unmaterializedFolders.isEmpty {
            do {
                try materializeAllSynchronously()
            } catch {
                return completionHandler(error)
            }
        }
        if !heldUnmaterialized.isEmpty || !heldUnmaterializedFolders.isEmpty {
            do {
                try materializeHeldSynchronously()
            } catch {
                return completionHandler(error)
            }
        }
        // What the saved entries will be linked to once the save is done. Taken before the clone, so a
        // file changed while the save writes, or even while it clones, no longer matches its entry and
        // is compressed afresh next time. Read after the save, it would vouch for bytes never written.
        let identities =
            (password == nil && workspace.isCreatedOnDisk) ? FileIdentity.all(in: workspace.contents) : [:]
        let snapshot: URL
        do {
            if workspace.isCreatedOnDisk {
                snapshot = try workspace.snapshot()
            } else {
                snapshot = workspace.folder.appendingPathComponent("Snapshot-\(UUID().uuidString)", isDirectory: true)
            }
        } catch {
            return completionHandler(error)
        }
        let delta = canUseDelta ? buildDeltaPlan(workspaceRoot: workspace.contents, snapshotRoot: snapshot) : nil
        let cancellation = Cancellation()
        pendingSave.value = SaveJob(
            contents: snapshot,
            password: password,
            compressionLevel: Settings.shared.compressionLevel,
            deltaPlan: delta,
            unmaterialized: unmaterialized,
            unmaterializedFolders: unmaterializedFolders,
            sourceURL: source ?? sourceSignature?.url,
            sourceHandle: sourceHandle,
            sourceQuarantine: sourceQuarantine,
            encoding: encoding,
            onSaveLog: onSaveLog,
            cancellation: cancellation
        )
        let autosave = saveOperation == .autosaveInPlaceOperation || saveOperation == .autosaveElsewhereOperation
        saving = Saving(cancellation: cancellation, autosave: autosave)
        // A quick save says nothing. One that takes a while shows how far it has got.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.saving?.cancellation === cancellation else { return }
            self.saving?.shown = true
            self.report("Saving…")
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            try? FileManager.default.removeItem(at: snapshot)
            MainActor.assumeIsolated {
                if self.saving?.shown == true { self.report(nil) }
                self.saving = nil
                if error == nil {
                    // Saved as a ZIP of its own, an import no longer answers to the file it came from.
                    if self.fileURL != nil, self.importedFrom != nil {
                        self.importedFrom = nil
                        self.onStatus?()
                    }
                    self.refreshTrackingAfterSave(to: url, for: saveOperation, identities: identities)
                    self.parentDocument?.childDidSave()
                    // Autosaves happen all the time and say nothing; a save the person asked for is heard.
                    if !autosave { self.announce("Saved “\(self.displayName ?? "archive")”") }
                }
            }
            completionHandler(error)
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        guard let job = pendingSave.take() else { throw CocoaError(.fileWriteUnknown) }
        unblockUserInteraction()
        var reported = -1
        let progressCallback: (Double) -> Bool = { done in
            let percent = Int(done * 100)
            if percent != reported {
                reported = percent
                DispatchQueue.main.async { self.saveProgressed(percent, job.cancellation) }
            }
            return !job.cancellation.isCancelled
        }
        do {
            if job.password == nil, let delta = job.deltaPlan {
                if SourceSignature.of(delta.sourceSignature.url) == delta.sourceSignature {
                    try ZipWriter.write(
                        items: delta.items,
                        sourceZip: delta.sourceSignature.url,
                        to: url,
                        compressionLevel: job.compressionLevel,
                        comment: delta.comment,
                        progress: progressCallback
                    )
                } else {
                    Self.logSourceChangedFallback(for: delta.sourceSignature.url, notify: job.onSaveLog)
                    try Self.materializeIntoSnapshot(job)
                    try Archive.writeZip(
                        from: job.contents, to: url, password: job.password,
                        compressionLevel: job.compressionLevel,
                        progress: progressCallback
                    )
                }
            } else {
                try Self.materializeIntoSnapshot(job)
                try Archive.writeZip(
                    from: job.contents, to: url, password: job.password,
                    compressionLevel: job.compressionLevel,
                    progress: progressCallback
                )
            }
        } catch ArchiveError.cancelled {
            // The one error AppKit never shows; the next autosave starts from the newer contents.
            throw CocoaError(.userCancelled)
        }
    }

    nonisolated private static func materializeIntoSnapshot(_ job: SaveJob) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: job.contents.path) {
            try fm.createDirectory(at: job.contents, withIntermediateDirectories: true)
        }
        guard !job.unmaterialized.isEmpty || !job.unmaterializedFolders.isEmpty else { return }
        for (folderPath, modified) in job.unmaterializedFolders {
            let folderURL = job.contents.appendingPathComponent(folderPath, isDirectory: true)
            if !fm.fileExists(atPath: folderURL.path) {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                if let modified {
                    try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: folderURL.path)
                }
            }
        }
        guard let srcURL = job.sourceURL else { return }
        for (path, entry) in job.unmaterialized {
            let destURL = job.contents.appendingPathComponent(path)
            if !fm.fileExists(atPath: destURL.path) {
                try Archive.extractEntry(
                    entry,
                    from: srcURL,
                    sourceHandle: job.sourceHandle,
                    to: destURL,
                    quarantineRoot: job.contents,
                    quarantineMark: job.sourceQuarantine,
                    encoding: job.encoding
                )
            }
        }
    }

    nonisolated private static func logSourceChangedFallback(
        for url: URL, notify: (@Sendable (String) -> Void)?
    ) {
        let message =
            "Source archive changed on disk since opening (\(url.lastPathComponent)); falling back to full write."
        logger.notice("\(message, privacy: .public)")
        fputs("Zipboy: \(message)\n", stderr)
        notify?(message)
    }

    /// Checks whether a workspace file at `path` is still untouched since unpacking from the source ZIP.
    func verbatimEntry(forPath path: String) -> ZipCatalog.Entry? {
        guard let workspace else { return nil }
        let fileURL = workspace.contents.appendingPathComponent(path)
        if workspace.isCreatedOnDisk, FileManager.default.fileExists(atPath: fileURL.path) {
            guard let current = FileIdentity.of(fileURL),
                let tracked = trackedByInode[current.inode],
                current == tracked.identity
            else { return nil }
            return tracked.entry
        }
        return unmaterialized[path]
    }

    private func buildDeltaPlan(
        workspaceRoot: URL, snapshotRoot: URL
    ) -> DeltaPlan? {
        guard password == nil,
            let catalog,
            let expectedSig = sourceSignature
        else { return nil }

        guard SourceSignature.of(expectedSig.url) == expectedSig else {
            Self.logSourceChangedFallback(for: expectedSig.url, notify: onSaveLog)
            return nil
        }
        let onDiskPaths: [String]
        if workspace?.isCreatedOnDisk == true {
            guard let scanned = try? Archive.contents(of: workspaceRoot) else { return nil }
            onDiskPaths = scanned
        } else {
            onDiskPaths = []
        }
        let onDiskSet = Set(onDiskPaths)

        var keyedItems: [(path: String, item: ZipWriter.Item)] = []
        keyedItems.reserveCapacity(onDiskPaths.count + unmaterialized.count)

        for path in onDiskPaths {
            let snapURL = snapshotRoot.appendingPathComponent(path)
            if let entry = verbatimEntry(forPath: path), !entry.isEncrypted {
                let renamed = path == entry.path ? nil : path
                keyedItems.append((path, .verbatim(entry, newPath: renamed)))
            } else {
                keyedItems.append((path, .workspace(url: snapURL, path: path)))
            }
        }

        for (path, entry) in unmaterialized where !onDiskSet.contains(path) && !entry.isEncrypted {
            let renamed = path == entry.path ? nil : path
            keyedItems.append((path, .verbatim(entry, newPath: renamed)))
        }

        for (folderPath, modified) in unmaterializedFolders where !onDiskSet.contains(folderPath) {
            let prefix = folderPath + "/"
            let hasDescendant =
                onDiskPaths.contains(where: { $0.hasPrefix(prefix) })
                || unmaterialized.keys.contains(where: { $0.hasPrefix(prefix) })
                || unmaterializedFolders.keys.contains(where: { $0 != folderPath && $0.hasPrefix(prefix) })
            guard !hasDescendant else { continue }
            if let dirEntry = unmaterializedDirEntries[folderPath], !dirEntry.isEncrypted {
                let targetDirPath = folderPath + "/"
                let renamed = targetDirPath == dirEntry.path ? nil : targetDirPath
                keyedItems.append((folderPath, .verbatim(dirEntry, newPath: renamed)))
            } else {
                let snapURL = snapshotRoot.appendingPathComponent(folderPath, isDirectory: true)
                try? FileManager.default.createDirectory(at: snapURL, withIntermediateDirectories: true)
                if let modified {
                    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: snapURL.path)
                }
                keyedItems.append((folderPath, .workspace(url: snapURL, path: folderPath)))
            }
        }

        keyedItems.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        return DeltaPlan(items: keyedItems.map(\.item), sourceSignature: expectedSig, comment: catalog.comment)
    }

    private func refreshTrackingAfterSave(
        to url: URL, for operation: NSDocument.SaveOperationType, identities: [String: FileIdentity]
    ) {
        guard password == nil, workspace != nil else {
            catalog = nil
            trackedByInode = [:]
            sourceSignature = nil
            return
        }
        let targetURL: URL? =
            switch operation {
            case .saveOperation, .saveAsOperation, .autosaveInPlaceOperation:
                fileURL ?? url
            default:
                nil
            }
        guard let targetURL, let freshCatalog = try? ZipCatalog.read(from: targetURL, encoding: encoding) else {
            return
        }
        try? materializeHeldSynchronously()
        try? sourceHandle?.close()
        sourceHandle = try? FileHandle(forReadingFrom: targetURL)
        recordProvenance(catalog: freshCatalog, sourceURL: targetURL) { identities[$0] }
    }

    private func recordProvenance(
        catalog: ZipCatalog?, sourceURL: URL?, identity: (_ path: String) -> FileIdentity?
    ) {
        self.catalog = catalog
        guard let catalog, let sourceURL, let sig = SourceSignature.of(sourceURL) else {
            trackedByInode = [:]
            sourceSignature = nil
            return
        }
        sourceSignature = sig
        var map: [UInt64: TrackedFile] = [:]
        var nextUnmaterialized: [String: ZipCatalog.Entry] = [:]
        var nextDirEntries: [String: ZipCatalog.Entry] = [:]
        for entry in catalog.entries {
            if entry.isDirectory {
                let dirPath = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                if !dirPath.isEmpty {
                    nextDirEntries[dirPath] = entry
                }
                continue
            }
            if let file = identity(entry.path) {
                if !entry.isSymlink {
                    map[file.inode] = TrackedFile(entry: entry, identity: file)
                }
            } else if unmaterialized[entry.path] != nil {
                nextUnmaterialized[entry.path] = entry
            }
        }
        trackedByInode = map
        unmaterialized = nextUnmaterialized
        unmaterializedDirEntries = nextDirEntries
    }

    private func saveProgressed(_ percent: Int, _ cancellation: Cancellation) {
        // Only the save still running, and only once it has been slow enough to mention.
        guard saving?.cancellation === cancellation, saving?.shown == true else { return }
        report("Saving… \(percent)%")
    }

    /// An edit makes an autosave in flight stale, so it stops rather than finish writing old contents.
    private func editsInvalidateAutosave() {
        if let saving, saving.autosave { saving.cancellation.cancel() }
    }

    private func report(_ text: String?) {
        activity = text
        onStatus?()
    }

    /// Starts long work the window can show and stop. Its title stands in the subtitle meanwhile.
    func beginTask(_ title: String, total: Int64) -> LongTask {
        let task = LongTask(title: title, total: total)
        tasks.append(task)
        TaskWatcher.shared.began(task)
        report(title)
        return task
    }

    func endTask(_ task: LongTask) {
        guard tasks.contains(where: { $0 === task }) else { return }
        tasks.removeAll { $0 === task }
        TaskWatcher.shared.ended(task, in: self)
        report(tasks.last?.title)
    }

    /// Stops the work on show, from the stop button or Escape.
    @objc func stopTask(_ sender: Any?) {
        tasks.last?.progress.cancel()
    }

    /// The file this archive came from, saved or not: for extracting beside it and previewing it.
    var source: URL? { fileURL ?? importedFrom?.url }

    /// A new document made from a RAR or tarball is saved beside it.
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if let folder = importedFrom?.url.deletingLastPathComponent() { savePanel.directoryURL = folder }
        return true
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(choosePassword(_:)):
            return loading == nil
        case #selector(removePassword(_:)):
            return loading == nil && password != nil
        case #selector(verifyArchive(_:)):
            return loading == nil && (source != nil || tree?.children.isEmpty == false)
        case #selector(exportArchive(_:)):
            return loading == nil && tree?.children.isEmpty == false
        case #selector(selectEncoding(_:)):
            if let menuItem = item as? NSMenuItem, let raw = menuItem.representedObject as? String {
                menuItem.state = (encoding.rawValue == raw) ? .on : .off
            }
            return canReload
        // Nothing to save or revert to while unpacking.
        case #selector(save(_:)), #selector(saveAs(_:)), #selector(revertToSaved(_:)):
            return loading == nil && super.validateUserInterfaceItem(item)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    private func install(_ workspace: Workspace, password: String?, catalog: ZipCatalog?, sourceURL: URL?) {
        Self.openDocuments.add(self)
        for task in materializingByPath.values { task.cancel() }
        materializingByPath.removeAll()
        watcher?.stop()
        watcher = nil
        try? sourceHandle?.close()
        sourceHandle = sourceURL.flatMap { try? FileHandle(forReadingFrom: $0) }
        sourceQuarantine = sourceURL.flatMap { Archive.quarantine(of: $0) }
        self.workspace?.discard()
        self.workspace = workspace
        self.password = password
        unmaterialized = [:]
        unmaterializedFolders = [:]
        unmaterializedDirEntries = [:]
        heldUnmaterialized = [:]
        heldUnmaterializedFolders = [:]
        loading = nil
        recordProvenance(catalog: catalog, sourceURL: sourceURL) {
            FileIdentity.of(workspace.contents.appendingPathComponent($0))
        }
        if workspace.isCreatedOnDisk {
            watcher = FileWatcher(workspace.contents) { [weak self] in self?.contentsMayHaveChanged() }
        }
        undoManager?.removeAllActions()
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        rescan()
    }

    private func installCatalog(
        _ workspace: Workspace,
        catalog: ZipCatalog,
        sourceURL: URL,
        sourceHandle: FileHandle?,
        quarantine: Data?
    ) {
        Self.openDocuments.add(self)
        for task in materializingByPath.values { task.cancel() }
        materializingByPath.removeAll()
        watcher?.stop()
        watcher = nil
        try? self.sourceHandle?.close()
        self.sourceHandle = sourceHandle
        self.sourceQuarantine = quarantine
        self.workspace?.discard()
        self.workspace = workspace
        self.password = nil
        self.catalog = catalog
        self.sourceSignature = SourceSignature.of(sourceURL)
        self.trackedByInode = [:]
        self.heldUnmaterialized = [:]
        self.heldUnmaterializedFolders = [:]

        var entriesByPath: [String: ZipCatalog.Entry] = [:]
        var foldersByPath: [String: Date?] = [:]
        var dirEntriesByPath: [String: ZipCatalog.Entry] = [:]

        for entry in catalog.entries {
            guard let cleanPath = EntryPath.sanitized(entry.path) else { continue }
            if entry.isDirectory {
                foldersByPath[cleanPath] = entry.modified
                dirEntriesByPath[cleanPath] = entry
                var parent = (cleanPath as NSString).deletingLastPathComponent
                while !parent.isEmpty && parent != "." {
                    if foldersByPath[parent] == nil { foldersByPath[parent] = nil }
                    parent = (parent as NSString).deletingLastPathComponent
                }
            } else {
                entriesByPath[cleanPath] = entry
                var parent = (cleanPath as NSString).deletingLastPathComponent
                while !parent.isEmpty && parent != "." {
                    if foldersByPath[parent] == nil { foldersByPath[parent] = nil }
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        }

        self.unmaterialized = entriesByPath
        self.unmaterializedFolders = foldersByPath
        self.unmaterializedDirEntries = dirEntriesByPath
        loading = nil
        undoManager?.removeAllActions()
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        rescan()
    }

    /// Ensures the given archive-relative `paths` (files or folders) are unpacked into the workspace
    /// and returns their workspace URLs. Concurrent calls for the same entry coalesce onto a single
    /// background extraction task.
    @discardableResult
    func materialize(
        _ paths: [String],
        progress: (@Sendable (Int64) -> Bool)? = nil
    ) async throws -> [URL] {
        guard let workspace else { throw CocoaError(.fileReadUnknown) }
        var results: [URL] = []
        results.reserveCapacity(paths.count)

        for rawPath in paths {
            let clean = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !clean.isEmpty else {
                try workspace.ensureCreated()
                ensureWatcherRunning()
                results.append(workspace.contents)
                continue
            }

            let prefix = clean + "/"
            let childEntries = unmaterialized.keys.filter { $0.hasPrefix(prefix) }.sorted()
            let childFolders = unmaterializedFolders.keys.filter { $0 == clean || $0.hasPrefix(prefix) }.sorted()

            if !childFolders.isEmpty || !childEntries.isEmpty {
                try workspace.ensureCreated()
                ensureWatcherRunning()
                let fm = FileManager.default
                for folder in childFolders {
                    let folderURL = workspace.url(folder)
                    if !fm.fileExists(atPath: folderURL.path) {
                        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                        if let mod = unmaterializedFolders[folder] ?? nil {
                            try? fm.setAttributes([.modificationDate: mod], ofItemAtPath: folderURL.path)
                        }
                        if let mark = sourceQuarantine {
                            Archive.setQuarantine(mark, on: folderURL)
                        }
                    }
                }
                for childPath in childEntries {
                    _ = try await materializeSingleEntry(childPath, progress: progress)
                }
                if unmaterialized[clean] != nil {
                    _ = try await materializeSingleEntry(clean, progress: progress)
                }
                signature = Self.signature(of: tree)
                results.append(workspace.url(clean))
            } else if unmaterialized[clean] != nil {
                let url = try await materializeSingleEntry(clean, progress: progress)
                results.append(url)
            } else {
                results.append(workspace.url(clean))
            }
        }
        return results
    }

    func isMaterializing(_ path: String) -> Bool {
        materializingByPath[path] != nil
    }

    func hasUnmaterializedItems(under path: String) -> Bool {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if unmaterialized[clean] != nil { return true }
        let prefix = clean + "/"
        if unmaterialized.keys.contains(where: { $0.hasPrefix(prefix) }) { return true }
        if unmaterializedFolders.keys.contains(where: { $0 == clean || $0.hasPrefix(prefix) }) {
            return !FileManager.default.fileExists(atPath: workspace?.url(clean).path ?? "")
        }
        return false
    }

    private func finishMaterializing(path: String, entry: ZipCatalog.Entry, url: URL) {
        materializingByPath.removeValue(forKey: path)
        if unmaterialized[path]?.localHeaderOffset == entry.localHeaderOffset {
            unmaterialized.removeValue(forKey: path)
        }
        if !entry.isDirectory && !entry.isSymlink, let id = FileIdentity.of(url) {
            trackedByInode[id.inode] = TrackedFile(entry: entry, identity: id)
        }
        signature = Self.signature(of: tree)
    }

    private func materializeSingleEntry(
        _ path: String,
        progress: (@Sendable (Int64) -> Bool)?
    ) async throws -> URL {
        guard let workspace else { throw CocoaError(.fileReadUnknown) }
        if let existingTask = materializingByPath[path] {
            return try await existingTask.value
        }
        guard let entry = unmaterialized[path] else {
            return workspace.url(path)
        }
        guard let srcURL = source ?? sourceSignature?.url else {
            throw ArchiveError.unreadable("Missing source archive.")
        }
        try workspace.ensureCreated()
        ensureWatcherRunning()
        materializationCounts[path, default: 0] += 1

        let destURL = workspace.url(path)
        let rootURL = workspace.contents
        let handle = sourceHandle
        let quarantine = sourceQuarantine
        let chosenEncoding = encoding

        let task = Task.detached(priority: .userInitiated) { [weak self] () throws -> URL in
            let clock = ContinuousClock()
            let start = clock.now
            try Archive.extractEntry(
                entry,
                from: srcURL,
                sourceHandle: handle,
                to: destURL,
                quarantineRoot: rootURL,
                quarantineMark: quarantine,
                encoding: chosenEncoding,
                progress: progress
            )
            let elapsed = clock.now - start
            await MainActor.run {
                self?.lastMaterializationDuration = elapsed
                self?.finishMaterializing(path: path, entry: entry, url: destURL)
            }
            return destURL
        }
        materializingByPath[path] = task
        do {
            return try await task.value
        } catch {
            materializingByPath.removeValue(forKey: path)
            throw error
        }
    }

    @discardableResult
    func materializeSynchronously(_ paths: [String]) throws -> [URL] {
        guard let workspace else { throw CocoaError(.fileReadUnknown) }
        var results: [URL] = []
        results.reserveCapacity(paths.count)
        let fm = FileManager.default

        for rawPath in paths {
            let clean = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !clean.isEmpty else {
                try workspace.ensureCreated()
                ensureWatcherRunning()
                results.append(workspace.contents)
                continue
            }

            let prefix = clean + "/"
            let childEntries = unmaterialized.keys.filter { $0.hasPrefix(prefix) }.sorted()
            let childFolders = unmaterializedFolders.keys.filter { $0 == clean || $0.hasPrefix(prefix) }.sorted()

            if !childFolders.isEmpty || !childEntries.isEmpty {
                try workspace.ensureCreated()
                ensureWatcherRunning()
                for folder in childFolders {
                    let folderURL = workspace.url(folder)
                    if !fm.fileExists(atPath: folderURL.path) {
                        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                        if let mod = unmaterializedFolders[folder] ?? nil {
                            try? fm.setAttributes([.modificationDate: mod], ofItemAtPath: folderURL.path)
                        }
                        if let mark = sourceQuarantine {
                            Archive.setQuarantine(mark, on: folderURL)
                        }
                    }
                }
                for childPath in childEntries {
                    _ = try materializeSingleEntrySynchronously(childPath)
                }
                if unmaterialized[clean] != nil {
                    _ = try materializeSingleEntrySynchronously(clean)
                }
                signature = Self.signature(of: tree)
                results.append(workspace.url(clean))
            } else if unmaterialized[clean] != nil {
                let url = try materializeSingleEntrySynchronously(clean)
                results.append(url)
            } else {
                results.append(workspace.url(clean))
            }
        }
        return results
    }

    func materializeURLSynchronously(_ url: URL) throws {
        guard let workspace, let relPath = relativeArchivePath(of: url, in: workspace) else { return }
        _ = try materializeSynchronously([relPath])
    }

    private func materializeSingleEntrySynchronously(_ path: String) throws -> URL {
        guard let workspace else { throw CocoaError(.fileReadUnknown) }
        let inFlight = materializingByPath.removeValue(forKey: path)
        inFlight?.cancel()
        guard let entry = unmaterialized[path] else {
            return workspace.url(path)
        }
        guard let srcURL = source ?? sourceSignature?.url else {
            throw ArchiveError.unreadable("Missing source archive.")
        }
        try workspace.ensureCreated()
        ensureWatcherRunning()
        let destURL = workspace.url(path)
        if !FileManager.default.fileExists(atPath: destURL.path) {
            if inFlight == nil {
                materializationCounts[path, default: 0] += 1
            }
            try Archive.extractEntry(
                entry,
                from: srcURL,
                sourceHandle: sourceHandle,
                to: destURL,
                quarantineRoot: workspace.contents,
                quarantineMark: sourceQuarantine,
                encoding: encoding
            )
        }
        finishMaterializing(path: path, entry: entry, url: destURL)
        return destURL
    }

    func materializeAllSynchronously() throws {
        guard let workspace else { return }
        guard !unmaterialized.isEmpty || !unmaterializedFolders.isEmpty else { return }
        try workspace.ensureCreated()
        ensureWatcherRunning()
        let fm = FileManager.default
        for (folderPath, modified) in unmaterializedFolders {
            let folderURL = workspace.url(folderPath)
            if !fm.fileExists(atPath: folderURL.path) {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                if let modified {
                    try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: folderURL.path)
                }
                if let mark = sourceQuarantine {
                    Archive.setQuarantine(mark, on: folderURL)
                }
            }
        }
        if let srcURL = source ?? sourceSignature?.url {
            for (path, entry) in unmaterialized {
                let destURL = workspace.url(path)
                if !fm.fileExists(atPath: destURL.path) {
                    materializationCounts[path, default: 0] += 1
                    try Archive.extractEntry(
                        entry,
                        from: srcURL,
                        sourceHandle: sourceHandle,
                        to: destURL,
                        quarantineRoot: workspace.contents,
                        quarantineMark: sourceQuarantine,
                        encoding: encoding
                    )
                    if !entry.isDirectory && !entry.isSymlink, let id = FileIdentity.of(destURL) {
                        trackedByInode[id.inode] = TrackedFile(entry: entry, identity: id)
                    }
                }
            }
        }
        unmaterialized.removeAll()
        signature = Self.signature(of: tree)
    }

    private func materializeHeldSynchronously() throws {
        guard let workspace else { return }
        guard !heldUnmaterialized.isEmpty || !heldUnmaterializedFolders.isEmpty else { return }
        try workspace.ensureCreated()
        let fm = FileManager.default
        for (spotKey, folders) in heldUnmaterializedFolders {
            for item in folders {
                let targetURL = URL(fileURLWithPath: spotKey + item.suffix)
                if !fm.fileExists(atPath: targetURL.path) {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                    if let modified = item.modified {
                        try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: targetURL.path)
                    }
                    if let mark = sourceQuarantine {
                        Archive.setQuarantine(mark, on: targetURL)
                    }
                }
            }
        }
        heldUnmaterializedFolders.removeAll()

        if let srcURL = source ?? sourceSignature?.url {
            for (spotKey, entries) in heldUnmaterialized {
                let spotRoot = URL(fileURLWithPath: spotKey).deletingLastPathComponent()
                for item in entries {
                    let targetURL = URL(fileURLWithPath: spotKey + item.suffix)
                    if !fm.fileExists(atPath: targetURL.path) {
                        try Archive.extractEntry(
                            item.entry,
                            from: srcURL,
                            sourceHandle: sourceHandle,
                            to: targetURL,
                            quarantineRoot: spotRoot,
                            quarantineMark: sourceQuarantine,
                            encoding: encoding
                        )
                    }
                }
            }
        }
        heldUnmaterialized.removeAll()
    }

    nonisolated static func extractPromisedItem(
        fromWorkspaceURL source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Bool)? = nil
    ) throws -> Bool {
        let context:
            (
                entries: [(relSuffix: String, entry: ZipCatalog.Entry)],
                folders: [(relSuffix: String, modified: Date?)],
                srcURL: URL,
                handle: FileHandle?,
                quarantine: Data?,
                encoding: TextEncoding
            )? = onMain {
                let stdURL = source.standardizedFileURL.path
                for doc in Self.openDocuments.allObjects {
                    guard let ws = doc.workspace else { continue }
                    let prefix = ws.contents.standardizedFileURL.path + "/"
                    guard stdURL.hasPrefix(prefix) else { continue }
                    let relPath = String(stdURL.dropFirst(prefix.count))
                    guard let srcURL = doc.source ?? doc.sourceSignature?.url else { continue }
                    let childPrefix = relPath + "/"
                    var entries: [(String, ZipCatalog.Entry)] = []
                    for (k, v) in doc.unmaterialized {
                        if k == relPath {
                            entries.append(("", v))
                        } else if k.hasPrefix(childPrefix) {
                            entries.append((String(k.dropFirst(relPath.count)), v))
                        }
                    }
                    var folders: [(String, Date?)] = []
                    for (k, mod) in doc.unmaterializedFolders {
                        if k == relPath {
                            folders.append(("", mod))
                        } else if k.hasPrefix(childPrefix) {
                            folders.append((String(k.dropFirst(relPath.count)), mod))
                        }
                    }
                    guard !entries.isEmpty || !folders.isEmpty else { return nil }
                    entries.sort { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
                    folders.sort { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
                    return (entries, folders, srcURL, doc.sourceHandle, doc.sourceQuarantine, doc.encoding)
                }
                return nil
            }
        guard let context else { return false }
        let fm = FileManager.default
        let isFolder =
            !context.folders.isEmpty
            || context.entries.contains(where: { !$0.relSuffix.isEmpty })
        let quarantineRoot = isFolder ? destination : destination.deletingLastPathComponent()

        if isFolder {
            if isDirectory(source) {
                try FileCopy.copy(source, to: destination) { bytes in
                    progress?(bytes) ?? true
                }
            } else {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            }
            if let mark = context.quarantine {
                Archive.setQuarantine(mark, on: destination)
            }
            for (suffix, modified) in context.folders where !suffix.isEmpty {
                let sub = destination.appendingPathComponent(String(suffix.dropFirst()), isDirectory: true)
                try fm.createDirectory(at: sub, withIntermediateDirectories: true)
                if let modified {
                    try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: sub.path)
                }
                if let mark = context.quarantine {
                    Archive.setQuarantine(mark, on: sub)
                }
            }
        }

        var completedPrior: Int64 = isFolder && isDirectory(source) ? FileCopy.size(of: [source]) : 0
        for (suffix, entry) in context.entries {
            let target =
                suffix.isEmpty
                ? destination
                : destination.appendingPathComponent(String(suffix.dropFirst()))
            try Archive.extractEntry(
                entry,
                from: context.srcURL,
                sourceHandle: context.handle,
                to: target,
                quarantineRoot: quarantineRoot,
                quarantineMark: context.quarantine,
                encoding: context.encoding
            ) { currentEntryBytes in
                guard let progress else { return true }
                return progress(completedPrior + currentEntryBytes)
            }
            completedPrior += Int64(clamping: entry.uncompressedSize)
        }
        return true
    }

    private func ensureWatcherRunning() {
        guard watcher == nil, let workspace, workspace.isCreatedOnDisk else { return }
        watcher = FileWatcher(workspace.contents) { [weak self] in self?.contentsMayHaveChanged() }
    }

    func symlinkTarget(for node: Node) -> String? {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: node.url.path) {
            return target
        }
        guard let entry = unmaterialized[node.path], entry.isSymlink,
            let srcURL = source ?? sourceSignature?.url
        else {
            return nil
        }
        return Archive.readSymlinkTarget(entry, from: srcURL, sourceHandle: sourceHandle)
    }

    /// "ZIP 2.0 (deflation)" says more than anyone wants in a subtitle.
    nonisolated static func shortName(_ format: String) -> String {
        let name = format.split(separator: " ").first.map(String.init) ?? format
        return name.isEmpty ? "Archive" : name
    }

    // MARK: Verify and Export

    @objc func verifyArchive(_ sender: Any?) {
        guard loading == nil else { return }
        if let sourceURL = source {
            let currentPassword = password
            let currentEncoding = encoding
            report("Verifying…")
            Task {
                defer { report(nil) }
                do {
                    let reportData = try await Task.detached {
                        try Archive.verify(sourceURL, password: currentPassword, encoding: currentEncoding)
                    }.value
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = "“\(sourceURL.lastPathComponent)” is intact."
                    let countText =
                        reportData.entryCount == 1 ? "1 entry" : "\(reportData.entryCount.formatted()) entries"
                    let sizeText = ByteCountFormatter.string(
                        fromByteCount: reportData.totalBytes, countStyle: .file)
                    alert.informativeText =
                        "Verified \(countText) (\(sizeText)) in \(reportData.format) format with no errors."
                    if let window = windowForSheet {
                        _ = await alert.beginSheetModal(for: window)
                    } else {
                        alert.runModal()
                    }
                } catch {
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Verification failed for “\(sourceURL.lastPathComponent)”."
                    alert.informativeText = error.localizedDescription
                    if let window = windowForSheet {
                        _ = await alert.beginSheetModal(for: window)
                    } else {
                        alert.runModal()
                    }
                }
            }
        } else if let tree {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "“\(displayName ?? "Archive")” is intact."
            let count = tree.descendantCount
            let countText = count == 1 ? "1 item" : "\(count.formatted()) items"
            let sizeText = ByteCountFormatter.string(fromByteCount: tree.size, countStyle: .file)
            alert.informativeText = "Verified \(countText) (\(sizeText)) in the workspace."
            if let window = windowForSheet {
                Task { _ = await alert.beginSheetModal(for: window) }
            } else {
                alert.runModal()
            }
        }
    }

    @objc func exportArchive(_ sender: Any?) {
        guard let window = windowForSheet, let workspace else { return }
        let panel = NSSavePanel()
        panel.prompt = "Export"
        panel.title = "Export Archive"
        panel.canCreateDirectories = true

        let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for fmt in ExportFormat.allCases {
            formatPopup.addItem(withTitle: fmt.title)
        }
        if let password, !password.isEmpty {
            formatPopup.autoenablesItems = false
            for (item, format) in zip(formatPopup.itemArray, ExportFormat.allCases) where format != .zip {
                item.isEnabled = false
                item.toolTip = "Only a ZIP archive can keep the password."
            }
        }
        let stem = source.map(Naming.stem) ?? defaultDraftName()
        panel.nameFieldStringValue = "\(stem).\(ExportFormat.zip.fileExtension)"
        panel.directoryURL = source?.deletingLastPathComponent()

        let accessory = NSStackView()
        accessory.orientation = .horizontal
        accessory.alignment = .firstBaseline
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        let label = NSTextField(labelWithString: "Format:")
        label.font = .systemFont(ofSize: 13)
        accessory.addArrangedSubview(label)
        accessory.addArrangedSubview(formatPopup)
        accessory.frame = NSRect(x: 0, y: 0, width: 320, height: 42)
        panel.accessoryView = accessory

        @MainActor
        final class FormatCoordinator: NSObject {
            let panel: NSSavePanel
            let popup: NSPopUpButton
            init(panel: NSSavePanel, popup: NSPopUpButton) {
                self.panel = panel
                self.popup = popup
            }
            @objc func formatChanged(_ sender: NSPopUpButton) {
                let format = ExportFormat.allCases[max(0, sender.indexOfSelectedItem)]
                let current = panel.nameFieldStringValue
                let cleanStem = Naming.stem(of: URL(fileURLWithPath: current))
                panel.nameFieldStringValue = "\(cleanStem).\(format.fileExtension)"
            }
        }
        let coordinator = FormatCoordinator(panel: panel, popup: formatPopup)
        formatPopup.target = coordinator
        formatPopup.action = #selector(FormatCoordinator.formatChanged(_:))

        panel.beginSheetModal(for: window) { response in
            _ = coordinator  // retain until sheet closes
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated {
                let format = ExportFormat.allCases[max(0, formatPopup.indexOfSelectedItem)]
                let level = Settings.shared.compressionLevel
                let currentPassword = self.password
                if !self.unmaterialized.isEmpty || !self.unmaterializedFolders.isEmpty {
                    try? self.materializeAllSynchronously()
                }
                guard let snapshot = try? workspace.snapshot() else { return }
                self.report("Exporting…")
                Task.detached {
                    defer {
                        try? FileManager.default.removeItem(at: snapshot)
                        DispatchQueue.main.async { self.report(nil) }
                    }
                    do {
                        try Archive.export(
                            from: snapshot,
                            to: destination,
                            format: format,
                            compressionLevel: level,
                            password: currentPassword
                        )
                    } catch {
                        _ = await MainActor.run { self.presentError(error) }
                    }
                }
            }
        }
    }

    // MARK: Contents

    private func rescan() {
        guard let workspace else { return }
        tree = Node.scan(
            workspace.contents,
            unmaterialized: unmaterialized,
            unmaterializedFolders: unmaterializedFolders
        )
        signature = Self.signature(of: tree)
        onChange?()
    }

    func childDidSave() {
        if let workspace {
            let fresh = Node.scan(
                workspace.contents,
                unmaterialized: unmaterialized,
                unmaterializedFolders: unmaterializedFolders
            )
            tree = fresh
            signature = Self.signature(of: fresh)
        }
        updateChangeCount(.changeDone)
        editsInvalidateAutosave()
        onChange?()
    }

    /// An app that opened a file from the archive saved over it. That can't be undone here, but the
    /// document must count as edited so the change is saved.
    func contentsMayHaveChanged() {
        guard let workspace, workspace.isCreatedOnDisk, materializingByPath.isEmpty else { return }
        let fresh = Node.scan(
            workspace.contents,
            unmaterialized: unmaterialized,
            unmaterializedFolders: unmaterializedFolders
        )
        let freshSignature = Self.signature(of: fresh)
        guard freshSignature != signature else { return }
        tree = fresh
        signature = freshSignature
        updateChangeCount(.changeDone)
        editsInvalidateAutosave()
        onChange?()
    }

    private static func signature(of tree: Node?) -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ node: Node) {
            for child in node.children {
                if child.isDirectory {
                    result[child.path] = "dir"
                } else {
                    result[child.path] = "\(child.size) \(Int(child.modified?.timeIntervalSince1970 ?? 0))"
                }
                walk(child)
            }
        }
        tree.map(walk)
        return result
    }

    private func relativeArchivePath(of url: URL, in workspace: Workspace) -> String? {
        let rootPath = workspace.contents.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(prefix) else { return nil }
        let rel = String(targetPath.dropFirst(prefix.count))
        return rel.isEmpty ? nil : rel
    }

    private func applyMove(_ move: Move, in workspace: Workspace) throws {
        let fm = FileManager.default
        let fromRel = relativeArchivePath(of: move.from, in: workspace)
        let toRel = relativeArchivePath(of: move.to, in: workspace)

        switch (fromRel, toRel) {
        case (.some(let src), .some(let dst)):
            if fm.fileExists(atPath: move.from.path) {
                try fm.createDirectory(
                    at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try move.perform()
            }
            moveUnmaterialized(from: src, to: dst)

        case (.some(let src), .none):
            let spotKey = move.to.standardizedFileURL.path
            if fm.fileExists(atPath: move.from.path) {
                try fm.createDirectory(
                    at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try move.perform()
            }
            stashUnmaterialized(from: src, intoSpot: spotKey)

        case (.none, .some(let dst)):
            let spotKey = move.from.standardizedFileURL.path
            if fm.fileExists(atPath: move.from.path) {
                try workspace.ensureCreated()
                ensureWatcherRunning()
                try fm.createDirectory(
                    at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try move.perform()
            }
            restoreUnmaterialized(fromSpot: spotKey, to: dst)

        case (.none, .none):
            try move.perform()
        }
    }

    private func moveUnmaterialized(from src: String, to dst: String) {
        let prefix = src + "/"
        var movedEntries: [(oldKey: String, newKey: String, entry: ZipCatalog.Entry)] = []
        for (key, entry) in unmaterialized {
            if key == src {
                movedEntries.append((key, dst, entry))
            } else if key.hasPrefix(prefix) {
                let suffix = String(key.dropFirst(src.count))
                movedEntries.append((key, dst + suffix, entry))
            }
        }
        for item in movedEntries { unmaterialized.removeValue(forKey: item.oldKey) }
        for item in movedEntries { unmaterialized[item.newKey] = item.entry }

        var movedFolders: [(oldKey: String, newKey: String, modified: Date?, dirEntry: ZipCatalog.Entry?)] = []
        for (key, modified) in unmaterializedFolders {
            if key == src {
                movedFolders.append((key, dst, modified, unmaterializedDirEntries[key]))
            } else if key.hasPrefix(prefix) {
                let suffix = String(key.dropFirst(src.count))
                movedFolders.append((key, dst + suffix, modified, unmaterializedDirEntries[key]))
            }
        }
        for item in movedFolders {
            unmaterializedFolders.removeValue(forKey: item.oldKey)
            unmaterializedDirEntries.removeValue(forKey: item.oldKey)
        }
        for item in movedFolders {
            unmaterializedFolders[item.newKey] = item.modified
            if let dirEntry = item.dirEntry {
                unmaterializedDirEntries[item.newKey] = dirEntry
            }
        }
        var parent = (dst as NSString).deletingLastPathComponent
        while !parent.isEmpty && parent != "." {
            if unmaterializedFolders[parent] == nil { unmaterializedFolders[parent] = nil }
            parent = (parent as NSString).deletingLastPathComponent
        }
    }

    private func stashUnmaterialized(from src: String, intoSpot spotKey: String) {
        let prefix = src + "/"
        var stashedEntries: [(suffix: String, entry: ZipCatalog.Entry)] = []
        for (key, entry) in unmaterialized {
            if key == src {
                stashedEntries.append(("", entry))
            } else if key.hasPrefix(prefix) {
                stashedEntries.append((String(key.dropFirst(src.count)), entry))
            }
        }
        for item in stashedEntries {
            unmaterialized.removeValue(forKey: src + item.suffix)
        }
        if !stashedEntries.isEmpty {
            heldUnmaterialized[spotKey] = stashedEntries
        }

        var stashedFolders: [(suffix: String, modified: Date?, dirEntry: ZipCatalog.Entry?)] = []
        for (key, modified) in unmaterializedFolders {
            if key == src {
                stashedFolders.append(("", modified, unmaterializedDirEntries[key]))
            } else if key.hasPrefix(prefix) {
                stashedFolders.append(
                    (String(key.dropFirst(src.count)), modified, unmaterializedDirEntries[key]))
            }
        }
        for item in stashedFolders {
            let oldKey = src + item.suffix
            unmaterializedFolders.removeValue(forKey: oldKey)
            unmaterializedDirEntries.removeValue(forKey: oldKey)
        }
        if !stashedFolders.isEmpty {
            heldUnmaterializedFolders[spotKey] = stashedFolders
        }
    }

    private func restoreUnmaterialized(fromSpot spotKey: String, to dst: String) {
        if let stashedEntries = heldUnmaterialized.removeValue(forKey: spotKey) {
            for item in stashedEntries {
                let key = dst + item.suffix
                unmaterialized[key] = item.entry
                var parent = (key as NSString).deletingLastPathComponent
                while !parent.isEmpty && parent != "." {
                    if unmaterializedFolders[parent] == nil { unmaterializedFolders[parent] = nil }
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        }
        if let stashedFolders = heldUnmaterializedFolders.removeValue(forKey: spotKey) {
            for item in stashedFolders {
                let key = dst + item.suffix
                unmaterializedFolders[key] = item.modified
                if let dirEntry = item.dirEntry {
                    unmaterializedDirEntries[key] = dirEntry
                }
                var parent = (key as NSString).deletingLastPathComponent
                while !parent.isEmpty && parent != "." {
                    if unmaterializedFolders[parent] == nil { unmaterializedFolders[parent] = nil }
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        }
    }

    private func takenNames(in folder: String, workspace: Workspace) -> Set<String> {
        var names = Set<String>()
        if workspace.isCreatedOnDisk {
            if let onDisk = try? FileManager.default.contentsOfDirectory(atPath: workspace.url(folder).path) {
                names.formUnion(onDisk)
            }
        }
        let prefix = folder.isEmpty ? "" : folder + "/"
        func collectChildName(from path: String) {
            if folder.isEmpty {
                if let first = path.split(separator: "/", maxSplits: 1).first {
                    names.insert(String(first))
                }
            } else if path.hasPrefix(prefix) {
                let rest = path.dropFirst(prefix.count)
                if let first = rest.split(separator: "/", maxSplits: 1).first {
                    names.insert(String(first))
                }
            }
        }
        for path in unmaterialized.keys { collectChildName(from: path) }
        for path in unmaterializedFolders.keys { collectChildName(from: path) }
        return names
    }

    private func isArchiveItemDirectory(path: String, in workspace: Workspace) -> Bool {
        if isDirectory(workspace.url(path)) { return true }
        if unmaterializedFolders[path] != nil { return true }
        let prefix = path + "/"
        return unmaterialized.keys.contains(where: { $0.hasPrefix(prefix) })
    }

    /// Runs renames in order and registers the reverse for undo. If one fails, the ones already done
    /// are put back so the workspace is never left half changed.
    func perform(_ moves: [Move], named actionName: String) throws {
        guard let workspace else { return }
        var done: [Move] = []
        do {
            for move in moves {
                try applyMove(move, in: workspace)
                done.append(move)
            }
        } catch {
            for move in done.reversed() { try? applyMove(move.inverted, in: workspace) }
            rescan()
            throw error
        }
        let reverse = moves.reversed().map(\.inverted)
        undoManager?.registerUndo(withTarget: self) { document in
            do {
                try document.perform(reverse, named: actionName)
            } catch {
                document.presentError(error)
            }
        }
        undoManager?.setActionName(actionName)
        editsInvalidateAutosave()
        rescan()
    }

    /// Copies items from outside into `folder`. Each name that is already there needs a `Resolution`.
    /// The copying runs off the main thread, since a dropped folder can be any size. Returns where
    /// each added item landed, under the name it ended up with.
    @discardableResult
    func add(_ urls: [URL], into folder: String, resolve: (String) async -> Prompts.Resolution?) async throws
        -> [String]
    {
        guard let workspace else { return [] }
        let fm = FileManager.default
        var plan: [(source: URL, name: String)] = []
        var replaced: [Move] = []
        var taken = takenNames(in: folder, workspace: workspace)
        for url in urls {
            var name = url.lastPathComponent
            let destination = workspace.url(folder).appendingPathComponent(name)
            if taken.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                guard let resolution = await resolve(name) else { break }
                switch resolution {
                case .skip: continue
                case .replace:
                    if url.standardizedFileURL == destination.standardizedFileURL { continue }
                    let spot =
                        fm.fileExists(atPath: destination.path)
                        ? try workspace.holdingSpot(for: name)
                        : workspace.virtualHoldingSpot(for: name)
                    replaced.append(Move(from: destination, to: spot))
                case .keepBoth:
                    name = Naming.unique(name, isDirectory: isDirectory(url), taken: taken)
                }
            }
            plan.append((url, name))
            taken.insert(name)
        }
        guard !plan.isEmpty else { return [] }

        let task = beginTask(
            plan.count == 1 ? "Adding “\(plan[0].name)”…" : "Adding \(plan.count) items…",
            total: FileCopy.size(of: plan.map(\.source)))
        defer { endTask(task) }
        let jobs = plan
        let progress = task.progress
        let clone = cloneWhenCopying
        let staged = try await Task.detached {
            var spots: [URL] = []
            var done: Int64 = 0
            do {
                return try jobs.map { job in
                    let spot = try workspace.holdingSpot(for: job.name)
                    spots.append(spot)
                    var copied: Int64 = 0
                    try FileCopy.copy(job.source, to: spot, clone: clone) { bytes in
                        copied = bytes
                        progress.completedUnitCount = done + bytes
                        return !progress.isCancelled
                    }
                    done += copied
                    Workspace.makeWritable(spot)
                    return Move(from: spot, to: workspace.url(folder).appendingPathComponent(job.name))
                }
            } catch {
                // Stopped or failed partway: nothing reaches the archive, and nothing is left staged.
                for spot in spots { try? FileManager.default.removeItem(at: spot.deletingLastPathComponent()) }
                throw error
            }
        }.value
        try perform(replaced + staged, named: plan.count == 1 ? "Add Item" : "Add Items")
        announce(plan.count == 1 ? "Added “\(plan[0].name)”" : "Added \(plan.count) items")
        return plan.map { folder.isEmpty ? $0.name : "\(folder)/\($0.name)" }
    }

    /// Sets the password the next save encrypts with, or with nil saves without one. Undoable, and
    /// counts as an edit, since it changes what Save writes.
    func setPassword(_ new: String?) {
        let old = password
        password = new
        if new == nil, let url = source {
            Keychain.deletePassword(for: url, service: keychainService)
        }
        undoManager?.registerUndo(withTarget: self) { $0.setPassword(old) }
        undoManager?.setActionName(new == nil ? "Remove Password" : "Set Password")
        editsInvalidateAutosave()
        onStatus?()
    }

    @objc func choosePassword(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        Task {
            if let entered = await Prompts.newPassword(in: window) {
                setPassword(entered.password)
                if entered.rememberInKeychain, let url = source {
                    do {
                        try Keychain.setPassword(entered.password, for: url, service: keychainService)
                    } catch {
                        reportKeychainFailure(error)
                    }
                }
            }
        }
    }

    @objc func removePassword(_ sender: Any?) {
        setPassword(nil)
    }

    /// The password is kept by path, so it moves with an archive renamed or moved in Finder while open.
    nonisolated override func presentedItemDidMove(to newURL: URL) {
        let old = fileURL
        super.presentedItemDidMove(to: newURL)
        guard let old else { return }
        DispatchQueue.main.async { self.passwordMoved(from: old, to: newURL) }
    }

    /// The same for File > Move To and renaming in the title bar, which this document does itself and so
    /// isn't told about as a file presenter.
    override func move(to url: URL, completionHandler: ((Error?) -> Void)? = nil) {
        let old = fileURL
        super.move(to: url) { error in
            MainActor.assumeIsolated {
                if error == nil, let old { self.passwordMoved(from: old, to: url) }
            }
            completionHandler?(error)
        }
    }

    private func passwordMoved(from old: URL, to new: URL) {
        guard password != nil else { return }
        do {
            try Keychain.movePassword(from: old, to: new, service: keychainService)
        } catch {
            reportKeychainFailure(error)
        }
    }

    /// The archive itself is fine; the person is told so that the next password prompt isn't a surprise.
    private func reportKeychainFailure(_ error: Error) {
        if let window = windowForSheet {
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            presentError(error)
        }
    }

    override func willPresentError(_ error: Error) -> Error {
        let nsError = error as NSError
        // Cancelling says nothing, and a Keychain failure already says what happened in its own words.
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError || error is Keychain.Failure {
            return error
        }
        let explanation = ArchiveError.describe(error, fileName: source?.lastPathComponent ?? displayName)
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: explanation.title,
            NSLocalizedRecoverySuggestionErrorKey: explanation.message,
        ]
        // The next step as a button, not an instruction to go and find it in a menu.
        if let recovery = explanation.recovery {
            let attempter = ErrorRecovery(recovery) { [weak self] in
                switch recovery {
                case .duplicate: self?.duplicate(nil)
                case .freeSpace: NSWorkspace.shared.open(ErrorRecovery.storageSettings)
                }
            }
            info[NSLocalizedRecoveryOptionsErrorKey] = [attempter.title, "Cancel"]
            info[NSRecoveryAttempterErrorKey] = attempter
        }
        return NSError(domain: nsError.domain, code: nsError.code, userInfo: info)
    }

    func remove(_ paths: [String]) throws {
        guard let workspace else { return }
        let fm = FileManager.default
        let moves = try paths.map { path -> Move in
            let src = workspace.url(path)
            let name = (path as NSString).lastPathComponent
            let spot =
                fm.fileExists(atPath: src.path)
                ? try workspace.holdingSpot(for: name)
                : workspace.virtualHoldingSpot(for: name)
            return Move(from: src, to: spot)
        }
        try perform(moves, named: paths.count == 1 ? "Delete Item" : "Delete Items")
        announce(
            paths.count == 1 ? "Deleted “\((paths[0] as NSString).lastPathComponent)”" : "Deleted \(paths.count) items")
    }

    func rename(_ path: String, to name: String) throws {
        guard let workspace else { return }
        let parent = (path as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? name : "\(parent)/\(name)"
        try perform([Move(from: workspace.url(path), to: workspace.url(target))], named: "Rename")
    }

    /// Moves items into another folder of the archive, numbering names that collide.
    func move(_ paths: [String], into folder: String) throws {
        guard let workspace else { return }
        var taken = takenNames(in: folder, workspace: workspace)
        var moves: [Move] = []
        // Into its own folder is no move, and into itself or below would lose it.
        for path in paths
        where (path as NSString).deletingLastPathComponent != folder && folder != path && !folder.hasPrefix(path + "/")
        {
            let source = workspace.url(path)
            let isDir = isArchiveItemDirectory(path: path, in: workspace)
            let name = Naming.unique(source.lastPathComponent, isDirectory: isDir, taken: taken)
            taken.insert(name)
            moves.append(Move(from: source, to: workspace.url(folder).appendingPathComponent(name)))
        }
        guard !moves.isEmpty else { return }
        try perform(moves, named: moves.count == 1 ? "Move Item" : "Move Items")
    }

    /// Makes "untitled folder" inside `folder` and returns its path.
    func newFolder(in folder: String) throws -> String {
        guard let workspace else { throw CocoaError(.fileWriteUnknown) }
        let taken = takenNames(in: folder, workspace: workspace)
        let name = Naming.unique("untitled folder", isDirectory: true, taken: taken)
        let staged = try workspace.holdingSpot(for: name)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false)
        let path = folder.isEmpty ? name : "\(folder)/\(name)"
        try perform([Move(from: staged, to: workspace.url(path))], named: "New Folder")
        return path
    }
}

func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
}

/// Runs `body` on the main thread, whether or not the caller is already there.
nonisolated func onMain<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try MainActor.assumeIsolated(body) }
    return try DispatchQueue.main.sync { try MainActor.assumeIsolated(body) }
}

/// A flag the unpacking thread checks between chunks.
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}

/// Long work the window shows and can stop: adding and extracting. `progress` counts bytes, and a
/// cancelled `progress` is how the work hears it should stop.
final class LongTask: Sendable {
    let title: String
    let progress: Progress
    let started: Date

    init(title: String, total: Int64, started: Date = Date()) {
        self.title = title
        self.started = started
        progress = Progress(totalUnitCount: max(total, 1))
    }
}

/// Carries out an error alert's first button, the recovery; the second is Cancel. AppKit calls one
/// method or the other depending on whether the alert is a sheet.
final class ErrorRecovery: NSObject {
    static let storageSettings = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!

    let title: String
    private let perform: () -> Void

    init(_ recovery: ArchiveError.Recovery, perform: @escaping () -> Void) {
        title =
            switch recovery {
            case .duplicate: "Duplicate…"
            case .freeSpace: "Open Storage Settings"
            }
        self.perform = perform
    }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int) -> Bool {
        guard recoveryOptionIndex == 0 else { return false }
        perform()
        return true
    }

    override func attemptRecovery(
        fromError error: Error, optionIndex recoveryOptionIndex: Int, delegate: Any?,
        didRecoverSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        let recovered = attemptRecovery(fromError: error, optionIndex: recoveryOptionIndex)
        if let delegate = delegate as? NSObject, let didRecoverSelector {
            // The selector's signature is (didRecover: Bool, contextInfo: void *); AppKit expects it called.
            typealias Callback = @convention(c) (AnyObject, Selector, Bool, UnsafeMutableRawPointer?) -> Void
            let call = unsafeBitCast(delegate.method(for: didRecoverSelector), to: Callback.self)
            call(delegate, didRecoverSelector, recovered, contextInfo)
        }
    }
}

/// What VoiceOver says when something changes out of the person's sight, such as items landing in the
/// list.
@MainActor
enum Announcer {
    static func say(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app.mainWindow ?? app, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// A value shared between threads behind a lock.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

extension Locked {
    /// Hands over the value once, leaving nil behind.
    func take<Wrapped>() -> Wrapped? where Value == Wrapped? {
        lock.withLock {
            defer { stored = nil }
            return stored
        }
    }
}
