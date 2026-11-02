import AppKit
import ZipboyKit

/// An archive unpacked into a workspace. Edits change the workspace and register their undo; saving
/// zips the workspace back up. Every readable format saves as ZIP, the one format worth writing.
@objc(ArchiveDocument)
final class ArchiveDocument: NSDocument {
    nonisolated static let zipType = "public.zip-archive"

    struct TrackedFile: Equatable, Sendable {
        let entry: ZipCatalog.Entry
        let inode: UInt64
        let size: Int64
        let modified: TimeInterval?
    }

    /// Enough of a workspace file to tell later whether it still holds the bytes an entry was made from.
    struct FileIdentity: Equatable, Sendable {
        let inode: UInt64
        let size: Int64
        let modified: TimeInterval?

        static func of(_ url: URL) -> FileIdentity? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                (attrs[.type] as? FileAttributeType) == .typeRegular,
                let inode = attrs[.systemFileNumber] as? UInt64,
                let size = attrs[.size] as? Int64
            else { return nil }
            return FileIdentity(
                inode: inode, size: size, modified: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970)
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
        let modified: TimeInterval?

        static func of(_ url: URL) -> SourceSignature? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                let inode = attrs[.systemFileNumber] as? UInt64,
                let size = attrs[.size] as? Int64
            else { return nil }
            let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
            return SourceSignature(url: url.standardizedFileURL, inode: inode, size: size, modified: mod)
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
    weak var parentDocument: ArchiveDocument?
    /// Original Central Directory catalog and per-inode file provenance for verbatim delta saves.
    private(set) var catalog: ZipCatalog?
    private(set) var trackedByInode: [UInt64: TrackedFile] = [:]
    private(set) var sourceSignature: SourceSignature?

    /// How far unpacking has got, from 0 to 1, or nil when the contents are ready.
    private(set) var loading: Double?
    private var cancelLoading = Cancellation()
    /// Long work under way after loading, such as "Saving… 40%", for the window's subtitle.
    private(set) var activity: String?
    private var saving: Saving?

    private struct SaveJob: Sendable {
        let contents: URL
        let password: String?
        let compressionLevel: Settings.CompressionLevel
        let deltaPlan: (items: [ZipWriter.Item], sourceZip: URL, comment: Data)?
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

    override func close() {
        cancelLoading.cancel()
        watcher?.stop()
        watcher = nil
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

    private func unpack(_ url: URL, ofType typeName: String) async {
        let cancellation = cancelLoading
        let chosenEncoding = encoding
        var password = self.password ?? Keychain.password(for: url)
        var usedSavedKeychain = (self.password == nil && password != nil)
        var rememberEnteredInKeychain = false
        while true {
            do {
                let (workspace, summary, parsedCatalog) = try await Task.detached { [password] in
                    let workspace = try Workspace()
                    do {
                        let summary = try Archive.extract(
                            url, into: workspace.contents, password: password, encoding: chosenEncoding
                        ) { done in
                            DispatchQueue.main.async { self.progressed(done, cancellation) }
                            return !cancellation.isCancelled
                        }
                        let catalog: ZipCatalog? =
                            if typeName == Self.zipType, !summary.encrypted {
                                try? ZipCatalog.read(from: url, encoding: chosenEncoding)
                            } else {
                                nil
                            }
                        return (workspace, summary, catalog)
                    } catch {
                        workspace.discard()
                        throw error
                    }
                }.value
                guard !cancellation.isCancelled else { return workspace.discard() }
                if summary.encrypted, rememberEnteredInKeychain, let password {
                    Keychain.setPassword(password, for: url)
                }
                install(
                    workspace,
                    password: summary.encrypted ? password : nil,
                    catalog: parsedCatalog,
                    sourceURL: typeName == Self.zipType ? url : nil
                )
                if typeName != Self.zipType {
                    importedFrom = (url, Self.shortName(summary.format))
                    fileURL = nil
                    fileType = Self.zipType
                    suggestedName = Naming.stem(of: url)
                }
                return
            } catch let error as ArchiveError where error == .passwordRequired || error == .wrongPassword {
                guard !cancellation.isCancelled else { return }
                if usedSavedKeychain {
                    Keychain.deletePassword(for: url)
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

    /// Re-reads the archive from its source file using `newEncoding` for non-UTF-8 entry names.
    func reload(withEncoding newEncoding: TextEncoding) {
        guard let sourceURL = source, loading == nil else { return }
        encoding = newEncoding
        let typeName = importedFrom == nil ? Self.zipType : "public.archive"
        cancelLoading.cancel()
        cancelLoading = Cancellation()
        loading = 0
        onChange?()
        Task { await unpack(sourceURL, ofType: typeName) }
    }

    @objc func selectEncoding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let chosen = TextEncoding(rawValue: raw)
        else { return }
        reload(withEncoding: chosen)
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
        // What the saved entries will be linked to once the save is done. Taken before the clone, so a
        // file changed while the save writes, or even while it clones, no longer matches its entry and
        // is compressed afresh next time. Read after the save, it would vouch for bytes never written.
        let identities = password == nil ? FileIdentity.all(in: workspace.contents) : [:]
        let snapshot: URL
        do {
            snapshot = try workspace.snapshot()
        } catch {
            return completionHandler(error)
        }
        let delta = buildDeltaPlan(workspaceRoot: workspace.contents, snapshotRoot: snapshot)
        let cancellation = Cancellation()
        pendingSave.value = SaveJob(
            contents: snapshot,
            password: password,
            compressionLevel: Settings.shared.compressionLevel,
            deltaPlan: delta,
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
                    self.refreshTrackingAfterSave(to: url, for: saveOperation, identities: identities)
                    self.parentDocument?.childDidSave()
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
                try ZipWriter.write(
                    items: delta.items,
                    sourceZip: delta.sourceZip,
                    to: url,
                    compressionLevel: job.compressionLevel,
                    comment: delta.comment,
                    progress: progressCallback
                )
            } else {
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

    /// Checks whether a workspace file at `path` is still untouched since unpacking from the source ZIP.
    func verbatimEntry(forPath path: String) -> ZipCatalog.Entry? {
        guard let workspace else { return nil }
        let fileURL = workspace.contents.appendingPathComponent(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let inode = attrs[.systemFileNumber] as? UInt64,
            let tracked = trackedByInode[inode]
        else { return nil }
        let currentSize = (attrs[.size] as? Int64) ?? 0
        let currentMod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
        guard currentSize == tracked.size else { return nil }
        if let expectedMod = tracked.modified, let currentMod, abs(currentMod - expectedMod) > 0.001 {
            return nil
        }
        return tracked.entry
    }

    private func buildDeltaPlan(
        workspaceRoot: URL, snapshotRoot: URL
    ) -> (items: [ZipWriter.Item], sourceZip: URL, comment: Data)? {
        guard password == nil,
            let catalog,
            let expectedSig = sourceSignature,
            let currentSig = SourceSignature.of(expectedSig.url),
            currentSig == expectedSig,
            let paths = try? Archive.contents(of: workspaceRoot)
        else { return nil }

        let fm = FileManager.default
        var items: [ZipWriter.Item] = []
        items.reserveCapacity(paths.count)

        for path in paths {
            let liveURL = workspaceRoot.appendingPathComponent(path)
            let snapURL = snapshotRoot.appendingPathComponent(path)
            if let attrs = try? fm.attributesOfItem(atPath: liveURL.path),
                (attrs[.type] as? FileAttributeType) == .typeRegular,
                let entry = verbatimEntry(forPath: path),
                !entry.isEncrypted
            {
                let renamed = path == entry.path ? nil : path
                items.append(.verbatim(entry, newPath: renamed))
            } else {
                items.append(.workspace(url: snapURL, path: path))
            }
        }
        return (items: items, sourceZip: expectedSig.url, comment: catalog.comment)
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
        for entry in catalog.entries where !entry.isDirectory && !entry.isSymlink {
            guard let file = identity(entry.path) else { continue }
            map[file.inode] = TrackedFile(entry: entry, inode: file.inode, size: file.size, modified: file.modified)
        }
        trackedByInode = map
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
            return loading == nil && source != nil
        // Nothing to save or revert to while unpacking.
        case #selector(save(_:)), #selector(saveAs(_:)), #selector(revertToSaved(_:)):
            return loading == nil && super.validateUserInterfaceItem(item)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    private func install(_ workspace: Workspace, password: String?, catalog: ZipCatalog?, sourceURL: URL?) {
        watcher?.stop()
        self.workspace?.discard()
        self.workspace = workspace
        self.password = password
        loading = nil
        recordProvenance(catalog: catalog, sourceURL: sourceURL) {
            FileIdentity.of(workspace.contents.appendingPathComponent($0))
        }
        watcher = FileWatcher(workspace.contents) { [weak self] in self?.contentsMayHaveChanged() }
        undoManager?.removeAllActions()
        rescan()
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
        tree = Node.scan(workspace.contents)
        signature = Self.signature(of: tree)
        onChange?()
    }

    func childDidSave() {
        if let workspace {
            let fresh = Node.scan(workspace.contents)
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
        guard let workspace else { return }
        let fresh = Node.scan(workspace.contents)
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
                result[child.path] = "\(child.size) \(child.modified?.timeIntervalSince1970 ?? 0)"
                walk(child)
            }
        }
        tree.map(walk)
        return result
    }

    /// Runs renames in order and registers the reverse for undo. If one fails, the ones already done
    /// are put back so the workspace is never left half changed.
    func perform(_ moves: [Move], named actionName: String) throws {
        var done: [Move] = []
        do {
            for move in moves {
                try move.perform()
                done.append(move)
            }
        } catch {
            for move in done.reversed() { try? move.inverted.perform() }
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
    /// The copying runs off the main thread, since a dropped folder can be any size.
    func add(_ urls: [URL], into folder: String, resolve: (String) async -> Prompts.Resolution?) async throws {
        guard let workspace else { return }
        let fm = FileManager.default
        var plan: [(source: URL, name: String)] = []
        var replaced: [Move] = []
        var taken = Set((try? fm.contentsOfDirectory(atPath: workspace.url(folder).path)) ?? [])
        for url in urls {
            var name = url.lastPathComponent
            let destination = workspace.url(folder).appendingPathComponent(name)
            if taken.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                guard let resolution = await resolve(name) else { break }
                switch resolution {
                case .skip: continue
                case .replace:
                    if url.standardizedFileURL == destination.standardizedFileURL { continue }
                    replaced.append(Move(from: destination, to: try workspace.holdingSpot(for: name)))
                case .keepBoth:
                    name = Naming.unique(name, isDirectory: isDirectory(url), taken: taken)
                }
            }
            plan.append((url, name))
            taken.insert(name)
        }
        guard !plan.isEmpty else { return }

        report(plan.count == 1 ? "Adding “\(plan[0].name)”…" : "Adding \(plan.count) items…")
        defer { report(nil) }
        let jobs = plan
        let staged = try await Task.detached {
            try jobs.map { job in
                let spot = try workspace.holdingSpot(for: job.name)
                try FileManager.default.copyItem(at: job.source, to: spot)
                Workspace.makeWritable(spot)
                return Move(from: spot, to: workspace.url(folder).appendingPathComponent(job.name))
            }
        }.value
        try perform(replaced + staged, named: plan.count == 1 ? "Add Item" : "Add Items")
    }

    /// Sets the password the next save encrypts with, or with nil saves without one. Undoable, and
    /// counts as an edit, since it changes what Save writes.
    func setPassword(_ new: String?) {
        let old = password
        password = new
        if new == nil, let url = source {
            Keychain.deletePassword(for: url)
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
                    Keychain.setPassword(entered.password, for: url)
                }
            }
        }
    }

    @objc func removePassword(_ sender: Any?) {
        setPassword(nil)
    }

    override func willPresentError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return error
        }
        let explanation = ArchiveError.describe(error, fileName: source?.lastPathComponent ?? displayName)
        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [
                NSLocalizedDescriptionKey: explanation.title,
                NSLocalizedRecoverySuggestionErrorKey: explanation.message,
            ]
        )
    }

    func remove(_ paths: [String]) throws {
        guard let workspace else { return }
        let moves = try paths.map {
            Move(from: workspace.url($0), to: try workspace.holdingSpot(for: ($0 as NSString).lastPathComponent))
        }
        try perform(moves, named: paths.count == 1 ? "Delete Item" : "Delete Items")
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
        var taken = Set((try? FileManager.default.contentsOfDirectory(atPath: workspace.url(folder).path)) ?? [])
        var moves: [Move] = []
        // Into its own folder is no move, and into itself or below would lose it.
        for path in paths
        where (path as NSString).deletingLastPathComponent != folder && folder != path && !folder.hasPrefix(path + "/")
        {
            let source = workspace.url(path)
            let name = Naming.unique(source.lastPathComponent, isDirectory: isDirectory(source), taken: taken)
            taken.insert(name)
            moves.append(Move(from: source, to: workspace.url(folder).appendingPathComponent(name)))
        }
        guard !moves.isEmpty else { return }
        try perform(moves, named: moves.count == 1 ? "Move Item" : "Move Items")
    }

    /// Makes "untitled folder" inside `folder` and returns its path.
    func newFolder(in folder: String) throws -> String {
        guard let workspace else { throw CocoaError(.fileWriteUnknown) }
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: workspace.url(folder).path)) ?? [])
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
