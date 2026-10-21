import AppKit
import ZipboyKit

/// An archive unpacked into a workspace. Edits change the workspace and register their undo; saving
/// zips the workspace back up. Every readable format saves as ZIP, the one format worth writing.
@objc(ArchiveDocument)
final class ArchiveDocument: NSDocument {
    nonisolated static let zipType = "public.zip-archive"

    private(set) var workspace: Workspace?
    private(set) var tree: Node?
    /// Set when the archive came from a format that can't be written back, such as RAR. Like Pages
    /// with a Word file, it then opens as a new document named after the original, and the original is
    /// never touched.
    private(set) var importedFrom: (url: URL, format: String)?
    /// Kept from opening an encrypted archive, so saving encrypts it again rather than quietly dropping
    /// the protection.
    private(set) var password: String?
    /// How far unpacking has got, from 0 to 1, or nil when the contents are ready.
    private(set) var loading: Double?
    private var cancelLoading = Cancellation()
    /// Long work under way after loading, such as "Saving… 40%", for the window's subtitle.
    private(set) var activity: String?
    private var saving: Saving?
    /// The snapshot the background save zips, handed from the main thread to the writing one.
    private let pendingSave = Locked<(contents: URL, password: String?, cancellation: Cancellation)?>(nil)

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
                install(try Workspace(), password: nil)
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
        var password: String?
        while true {
            do {
                let (workspace, summary) = try await Task.detached { [password] in
                    let workspace = try Workspace()
                    do {
                        let summary = try Archive.extract(url, into: workspace.contents, password: password) { done in
                            DispatchQueue.main.async { self.progressed(done, cancellation) }
                            return !cancellation.isCancelled
                        }
                        return (workspace, summary)
                    } catch {
                        workspace.discard()
                        throw error
                    }
                }.value
                guard !cancellation.isCancelled else { return workspace.discard() }
                install(workspace, password: summary.encrypted ? password : nil)
                if typeName != Self.zipType {
                    importedFrom = (url, Self.shortName(summary.format))
                    fileURL = nil
                    fileType = Self.zipType
                    suggestedName = url.deletingPathExtension().lastPathComponent
                }
                return
            } catch let error as ArchiveError where error == .passwordRequired || error == .wrongPassword {
                guard !cancellation.isCancelled else { return }
                let entered = await Prompts.password(
                    for: url.lastPathComponent, retry: error == .wrongPassword, in: windowForSheet)
                guard let entered else { return close() }
                password = entered
            } catch {
                guard !cancellation.isCancelled else { return }
                // The window has nothing to show, so it goes once the error is read.
                let failure = CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [
                        NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” couldn’t be opened.",
                        NSLocalizedRecoverySuggestionErrorKey: error.localizedDescription,
                    ])
                if let window = windowForSheet {
                    _ = await NSAlert(error: failure).beginSheetModal(for: window)
                } else {
                    presentError(failure)
                }
                return close()
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
        get { fileURL == nil ? defaultDraftName() : super.displayName }
        set { super.displayName = newValue }
    }

    /// The empty window from launch, which an opened archive takes the place of, as in TextEdit.
    var isTransient: Bool {
        fileURL == nil && importedFrom == nil && !isDocumentEdited && loading == nil
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
        let snapshot: URL
        do {
            snapshot = try workspace.snapshot()
        } catch {
            return completionHandler(error)
        }
        let cancellation = Cancellation()
        pendingSave.value = (snapshot, password, cancellation)
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
            }
            completionHandler(error)
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        guard let job = pendingSave.take() else { throw CocoaError(.fileWriteUnknown) }
        unblockUserInteraction()
        var reported = -1
        do {
            try Archive.writeZip(from: job.contents, to: url, password: job.password) { done in
                let percent = Int(done * 100)
                if percent != reported {
                    reported = percent
                    DispatchQueue.main.async { self.saveProgressed(percent, job.cancellation) }
                }
                return !job.cancellation.isCancelled
            }
        } catch ArchiveError.cancelled {
            // The one error AppKit never shows; the next autosave starts from the newer contents.
            throw CocoaError(.userCancelled)
        }
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
        case #selector(choosePassword(_:)): loading == nil
        case #selector(removePassword(_:)): loading == nil && password != nil
        // Nothing to save or revert to while unpacking.
        case #selector(save(_:)), #selector(saveAs(_:)), #selector(revertToSaved(_:)):
            loading == nil && super.validateUserInterfaceItem(item)
        default: super.validateUserInterfaceItem(item)
        }
    }

    private func install(_ workspace: Workspace, password: String?) {
        watcher?.stop()
        self.workspace?.discard()
        self.workspace = workspace
        self.password = password
        loading = nil
        watcher = FileWatcher(workspace.contents) { [weak self] in self?.contentsMayHaveChanged() }
        undoManager?.removeAllActions()
        rescan()
    }

    /// "ZIP 2.0 (deflation)" says more than anyone wants in a subtitle.
    nonisolated static func shortName(_ format: String) -> String {
        let name = format.split(separator: " ").first.map(String.init) ?? format
        return name.isEmpty ? "Archive" : name
    }

    // MARK: Contents

    private func rescan() {
        guard let workspace else { return }
        tree = Node.scan(workspace.contents)
        signature = Self.signature(of: tree)
        onChange?()
    }

    /// An app that opened a file from the archive saved over it. That can't be undone here, but the
    /// document must count as edited so the change is saved.
    private func contentsMayHaveChanged() {
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
        undoManager?.registerUndo(withTarget: self) { $0.setPassword(old) }
        undoManager?.setActionName(new == nil ? "Remove Password" : "Set Password")
        editsInvalidateAutosave()
        onStatus?()
    }

    @objc func choosePassword(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        Task {
            if let entered = await Prompts.newPassword(in: window) { setPassword(entered) }
        }
    }

    @objc func removePassword(_ sender: Any?) {
        setPassword(nil)
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
