import AppKit
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ZipboyKit

/// The archive as a Finder-style list. Files drag in from anywhere and out to anywhere, space bar opens
/// Quick Look, Return renames, and every edit can be undone.
@MainActor
final class BrowserViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSMenuDelegate, NSUserInterfaceValidations, NSTextFieldDelegate, @preconcurrency QLPreviewPanelDataSource,
    @preconcurrency QLPreviewPanelDelegate, NSFilePromiseProviderDelegate
{
    weak var document: ArchiveDocument?
    var onSelectionChange: (([Node]) -> Void)?

    let outline = BrowserOutlineView()
    private let empty = EmptyStateView()
    /// The tree on screen: the document's, or a filtered copy while searching.
    private var shown: Node?
    private var query = ""
    /// The folders open when a search began. A search opens every folder holding a match, so its own
    /// state is no guide to what to put back when it ends.
    private var openBeforeSearch: [String] = []
    private var sortKey = Node.SortKey.name
    private var ascending = true
    /// Paths being dragged from this list, to tell a move inside the archive from an add.
    var dragged: [String] = []
    private var shownOnce = false
    /// Kept so it can come back after an empty archive hides it.
    private var header: NSTableHeaderView?
    /// Picture previews for the name column, keyed by path and date so an edited file gets a new one.
    private var thumbnails: [String: NSImage] = [:]
    private var requested: Set<String> = []
    private var settingsObserver: NSObjectProtocol?
    private var springLoadWorkItem: DispatchWorkItem?
    private var springLoadTargetPath: String?
    var springLoadDelay: TimeInterval = 0.7
    /// Opens a loose file from the archive in Launch Services; replaced in tests so nothing launches.
    var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Reveals extracted files in Finder; replaced in tests so no Finder window opens.
    var revealFiles: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    /// State from the last session, held until the archive has finished opening.
    private var pendingRestore: SavedState?

    /// What a relaunch puts back: the open folders, the selection, and the search.
    struct SavedState: Equatable {
        var expanded: [String]
        var selected: [String]
        var query: String
    }

    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let modifiedColumn = NSUserInterfaceItemIdentifier("modified")
    private static let sizeColumn = NSUserInterfaceItemIdentifier("size")
    private static let kindColumn = NSUserInterfaceItemIdentifier("kind")

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = outline

        addColumn(Self.nameColumn, "Name", width: 300, min: 140, key: .name)
        addColumn(Self.modifiedColumn, "Date Modified", width: 150, min: 90, key: .modified)
        addColumn(Self.sizeColumn, "Size", width: 76, min: 60, key: .size, ascending: false)
        addColumn(Self.kindColumn, "Kind", width: 170, min: 60, key: .kind)
        outline.outlineTableColumn = outline.tableColumns.first
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = false
        outline.rowHeight = 24
        outline.allowsMultipleSelection = true
        outline.autoresizesOutlineColumn = false
        // The last column takes up the slack, so rows end where the list does.
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.autosaveName = "ArchiveColumns"
        outline.autosaveTableColumns = true
        // Before the delegate is set, which would hear of it and reload a list that isn't loaded yet.
        outline.sortDescriptors = [NSSortDescriptor(key: sortKey.rawValue, ascending: ascending)]
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(openItems(_:))
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outline.draggingDestinationFeedbackStyle = .regular
        outline.menu = NSMenu()
        outline.menu?.delegate = self

        header = outline.headerView
        outline.onDragDone = { [weak self] in self?.dropEnded() }

        // Inside the outline, so a drop on the message still lands on the list.
        empty.frame = outline.bounds
        empty.autoresizingMask = [.width, .height]
        outline.addSubview(empty)
        view = scroll

        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Widths saved from a wider window would push the last column, and the rows, past the edge.
        outline.sizeLastColumnToFit()
    }

    private func addColumn(
        _ id: NSUserInterfaceItemIdentifier, _ title: String, width: CGFloat, min: CGFloat, key: Node.SortKey,
        ascending: Bool = true
    ) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = min
        column.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: ascending)
        if id == Self.sizeColumn { column.headerCell.alignment = .right }
        outline.addTableColumn(column)
    }

    // MARK: Contents

    /// Rebuilds the list from the document, keeping what was open and selected, or opening `restoring`
    /// instead and revealing the selection inside it.
    func reload(restoring: [String]? = nil) {
        loadViewIfNeeded()
        if let done = document?.loading {
            empty.mode = .loading(done)
            empty.isHidden = false
            showHeader(false)
            return
        }
        guard let tree = document?.tree else { return }
        if let state = pendingRestore {
            pendingRestore = nil
            return restore(state)
        }
        let open = restoring ?? expandedPaths()
        let selected = selection.map(\.path)

        tree.sort(
            by: sortKey, ascending: ascending, foldersFirst: Settings.shared.keepFoldersOnTop)
        shown = tree.filtered(query, showHiddenFiles: Settings.shared.showHiddenFiles)
        outline.reloadData()
        if !shownOnce, Settings.shared.autoExpandSingleFolder,
            let only = shown?.children.first, shown?.children.count == 1, only.isDirectory
        {
            // Most archives wrap everything in one folder; opening it saves the first click.
            outline.expandItem(only)
        }
        shownOnce = true
        if query.isEmpty {
            for path in open { expand(path) }
        } else {
            outline.expandItem(nil, expandChildren: true)
        }
        if restoring != nil { reveal(selected) } else { select(selected) }

        let hasRows = shown?.children.isEmpty == false
        empty.isHidden = hasRows
        empty.mode = query.isEmpty ? .drop : .noResults(query)
        // Column headers over nothing are noise; they come back with the first item.
        showHeader(tree.children.isEmpty == false)
        selectionChanged()
    }

    private func showHeader(_ show: Bool) {
        let wanted = show ? header : nil
        guard outline.headerView !== wanted else { return }
        outline.headerView = wanted
        outline.enclosingScrollView?.tile()
    }

    var savedState: SavedState {
        SavedState(
            expanded: query.isEmpty ? expandedPaths() : openBeforeSearch, selected: selection.map(\.path), query: query)
    }

    /// Puts back a saved state, once the archive is open. Paths no longer in the archive are passed over.
    func restore(_ state: SavedState) {
        guard document?.tree != nil, document?.loading == nil else {
            pendingRestore = state
            return
        }
        query = state.query
        openBeforeSearch = state.expanded
        reload(restoring: query.isEmpty ? state.expanded : nil)
        reveal(state.selected)
    }

    func filter(_ text: String) {
        let next = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty, !next.isEmpty { openBeforeSearch = expandedPaths() }
        let ending = !query.isEmpty && next.isEmpty
        query = next
        reload(restoring: ending ? openBeforeSearch : nil)
    }

    private func expandedPaths() -> [String] {
        (0..<outline.numberOfRows).compactMap { row in
            guard let node = outline.item(atRow: row) as? Node, outline.isItemExpanded(node) else { return nil }
            return node.path
        }
    }

    private func expand(_ path: String) {
        var prefix = ""
        for part in path.split(separator: "/") {
            prefix = prefix.isEmpty ? String(part) : "\(prefix)/\(part)"
            if let node = shown?.find(prefix) { outline.expandItem(node) }
        }
    }

    func select(_ paths: [String]) {
        let rows = IndexSet(paths.compactMap { shown?.find($0) }.map { outline.row(forItem: $0) }.filter { $0 >= 0 })
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { outline.scrollRowToVisible(first) }
    }

    /// Opens the folders leading to `paths` and selects them.
    private func reveal(_ paths: [String]) {
        for path in paths { expand((path as NSString).deletingLastPathComponent) }
        select(paths)
    }

    var selection: [Node] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Node }
    }

    /// The right-clicked row if it's outside the selection, as Finder does; otherwise the selection.
    private var targets: [Node] {
        let clicked = outline.clickedRow
        if clicked >= 0, !outline.selectedRowIndexes.contains(clicked), let node = outline.item(atRow: clicked) as? Node
        {
            return [node]
        }
        return selection
    }

    /// Where new things go: into a selected folder, beside a selected file, or at the top.
    private var targetFolder: String {
        guard targets.count == 1, let node = targets.first else { return "" }
        return node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
    }

    private func selectionChanged() {
        onSelectionChange?(selection)
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    // MARK: Actions

    @objc func addFiles(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        let folder = targetFolder
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { _ = self.add(panel.urls, into: folder) }
        }
    }

    /// Adds in the background; the task is returned so a caller can wait for the items to show.
    @discardableResult
    func add(_ urls: [URL], into folder: String) -> Task<Void, Never>? {
        guard let document, !urls.isEmpty else { return nil }
        let conflicts = Prompts.Conflicts(window: view.window, count: urls.count)
        return Task {
            do {
                // Shown and selected where they landed, so what was added is never a mystery.
                reveal(try await document.add(urls, into: folder) { await conflicts.resolve($0) })
            } catch ArchiveError.cancelled {
                // Stopped on purpose; the archive is as it was, and there's nothing to say.
            } catch {
                document.presentError(error)
            }
        }
    }

    @objc func newFolder(_ sender: Any?) {
        guard let document else { return }
        do {
            let path = try document.newFolder(in: targetFolder)
            reveal([path])
            beginRename(at: outline.selectedRow)
        } catch {
            document.presentError(error)
        }
    }

    @objc func rename(_ sender: Any?) {
        guard targets.count == 1, let node = targets.first else { return }
        beginRename(at: outline.row(forItem: node))
    }

    /// Edits the name in place with the extension left out of the selection, as Finder does.
    private func beginRename(at row: Int) {
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.editColumn(0, row: row, with: nil, select: true)
        let base = node.isDirectory ? node.name : (node.name as NSString).deletingPathExtension
        outline.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    /// Escape puts the old name back and stops editing, as in Finder, rather than committing it.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField else {
            return false
        }
        let row = outline.row(for: field)
        if let node = outline.item(atRow: row) as? Node { field.stringValue = node.name }
        field.abortEditing()
        view.window?.makeFirstResponder(outline)
        return true
    }

    @objc private func nameEdited(_ sender: NSTextField) {
        let row = outline.row(for: sender)
        guard row >= 0, let node = outline.item(atRow: row) as? Node, let document else { return }
        let name = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard name != node.name else { return }
        let siblings = node.parent?.children ?? []
        let problem: String? =
            if name.isEmpty || name == "." || name == ".." { "That name can’t be used." } else if name.contains("/") {
                "Names can’t contain “/”."
            } else if siblings.contains(where: { $0 !== node && $0.name.caseInsensitiveCompare(name) == .orderedSame })
            {
                "The name “\(name)” is already taken. Please choose a different name."
            } else { nil }
        if let problem {
            sender.stringValue = node.name
            let alert = NSAlert()
            alert.messageText = problem
            if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        do {
            let parent = (node.path as NSString).deletingLastPathComponent
            try document.rename(node.path, to: name)
            reveal([parent.isEmpty ? name : "\(parent)/\(name)"])
        } catch {
            sender.stringValue = node.name
            document.presentError(error)
        }
    }

    @objc func delete(_ sender: Any?) {
        guard let document, !targets.isEmpty else { return }
        let row = outline.row(forItem: targets.first)
        do {
            try document.remove(targets.map(\.path))
            // Keep the cursor where it was, as Finder does after moving to the Trash.
            let next = min(row, outline.numberOfRows - 1)
            if next >= 0 { outline.selectRowIndexes([next], byExtendingSelection: false) }
        } catch {
            document.presentError(error)
        }
    }

    @objc func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(targets.map { $0.url as NSURL })
    }

    @objc func paste(_ sender: Any?) {
        add(Self.fileURLs(on: .general), into: targetFolder)
    }

    override func selectAll(_ sender: Any?) {
        outline.selectAll(sender)
    }

    @objc func openItems(_ sender: Any?) {
        let nodes = sender as? NSOutlineView === outline && outline.clickedRow >= 0 ? targets : selection
        for node in nodes {
            if node.isDirectory {
                outline.isItemExpanded(node) ? outline.collapseItem(node) : outline.expandItem(node)
            } else if Self.isNestedArchive(node.url) {
                openNestedArchive(at: node.url)
            } else {
                openFile(node.url)
            }
        }
    }

    static func isNestedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ZipMethod.archiveExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .archive) { return true }
        return false
    }

    func openNestedArchive(at url: URL) {
        let parent = document
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            MainActor.assumeIsolated {
                if let error {
                    parent?.presentError(error)
                    return
                }
                if let child = doc as? ArchiveDocument {
                    child.parentDocument = parent
                    child.windowControllers.first?.synchronizeWindowTitleWithDocumentName()
                }
            }
        }
    }

    @objc func expandAll(_ sender: Any?) {
        outline.expandItem(nil, expandChildren: true)
    }

    @objc func collapseAll(_ sender: Any?) {
        outline.collapseItem(nil, collapseChildren: true)
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        Settings.shared.showHiddenFiles.toggle()
    }

    // MARK: Extracting

    /// Extracts to the configured default destination, or asks where when needed.
    @objc func extract(_ sender: Any?) {
        switch Settings.shared.extractDestination {
        case .archiveFolder:
            guard let folder = document?.source?.deletingLastPathComponent() else {
                return extractTo(sender)
            }
            extract(into: folder)
        case .downloads:
            guard
                let downloads = FileManager.default.urls(
                    for: .downloadsDirectory, in: .userDomainMask
                ).first
            else {
                return extractTo(sender)
            }
            extract(into: downloads)
        case .alwaysAsk:
            extractTo(sender)
        }
    }

    @objc func extractTo(_ sender: Any?) {
        guard let window = view.window else { return }
        let items = targets
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Extract"
        panel.message =
            items.isEmpty
            ? "Choose where to extract “\(document?.displayName ?? "the archive")”."
            : "Choose where to extract \(items.count == 1 ? "“\(items[0].name)”" : "\(items.count) items")."
        panel.directoryURL = document?.source?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = panel.url else { return }
            MainActor.assumeIsolated { _ = self.extract(into: folder, items: items) }
        }
    }

    /// The selection comes out as it is. The whole archive comes out as its one top-level item, or as a
    /// folder named after the archive holding everything, so nothing ends up in a folder inside a
    /// folder of the same name, and nothing is scattered loose.
    @discardableResult
    func extract(into folder: URL, items chosen: [Node]? = nil) -> Task<Void, Never>? {
        let items = chosen ?? targets
        let whole = items.isEmpty
        let urls = whole ? (document?.tree?.children.map(\.url) ?? []) : items.map(\.url)
        guard !urls.isEmpty else { return nil }
        let wrap: Bool =
            switch Settings.shared.wrapExtractedFiles {
            case .whenMultipleItems: whole && urls.count > 1
            case .always: whole
            case .never: false
            }
        let revealInFinder = Settings.shared.revealExtractedInFinder
        let base = document?.source.map(Naming.stem) ?? "Archive"
        let sourceArchive = document?.source
        guard let document else { return nil }
        let task = document.beginTask(
            whole
                ? "Extracting “\(document.displayName ?? "Archive")”…"
                : urls.count == 1 ? "Extracting “\(urls[0].lastPathComponent)”…" : "Extracting \(urls.count) items…",
            total: FileCopy.size(of: urls))
        let progress = task.progress
        let clone = document.cloneWhenCopying
        return Task.detached { [weak self] in
            defer { Task { @MainActor in document.endTask(task) } }
            var destination = folder
            do {
                if wrap {
                    let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                    destination = folder.appendingPathComponent(Naming.unique(base, isDirectory: true, taken: taken))
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                    let markSource =
                        sourceArchive.flatMap { Archive.quarantine(of: $0) != nil ? $0 : nil } ?? urls.first
                    if let markSource { Archive.copyQuarantine(from: markSource, to: destination) }
                }
                let copied = try Self.copy(urls, into: destination, progress: progress, clone: clone)
                if revealInFinder {
                    let shown = wrap ? [destination] : copied
                    await MainActor.run { self?.revealFiles(shown) }
                }
            } catch {
                // The folder made to hold everything goes too, so a stopped extract leaves no trace.
                if wrap { try? FileManager.default.removeItem(at: destination) }
                if case ArchiveError.cancelled = error { return }
                await MainActor.run { _ = NSApp.presentError(error) }
            }
        }
    }

    /// Copies into `folder`, numbering any name that is already there rather than overwriting it.
    /// Each item shows Finder's progress pie while it copies. Stopped through `progress`, it removes
    /// everything it copied, and throws `ArchiveError.cancelled`.
    nonisolated static func copy(_ urls: [URL], into folder: URL, progress: Progress, clone: Bool = true) throws
        -> [URL]
    {
        var taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        var copied: [URL] = []
        var done: Int64 = 0
        do {
            for url in urls {
                let name = Naming.unique(url.lastPathComponent, isDirectory: isDirectory(url), taken: taken)
                taken.insert(name)
                let destination = folder.appendingPathComponent(name)
                let pie = Progress(totalUnitCount: max(FileCopy.size(of: [url]), 1))
                pie.kind = .file
                pie.fileOperationKind = .copying
                pie.fileURL = destination
                pie.publish()
                defer { pie.unpublish() }
                var bytes: Int64 = 0
                try FileCopy.copy(url, to: destination, clone: clone) {
                    bytes = $0
                    pie.completedUnitCount = $0
                    progress.completedUnitCount = done + $0
                    return !progress.isCancelled
                }
                done += bytes
                copied.append(destination)
            }
        } catch {
            for url in copied { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return copied
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    // MARK: Validation

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(rename(_:)): return targets.count == 1
        case #selector(delete(_:)), #selector(copy(_:)), #selector(openItems(_:)):
            return !targets.isEmpty
        case #selector(toggleQuickLook(_:)): return !selection.isEmpty
        case #selector(extract(_:)), #selector(extractTo(_:)): return document?.tree?.children.isEmpty == false
        case #selector(paste(_:)): return !Self.fileURLs(on: .general).isEmpty
        case #selector(addFiles(_:)), #selector(newFolder(_:)), #selector(selectAll(_:)), #selector(expandAll(_:)),
            #selector(collapseAll(_:)):
            return true
        case #selector(toggleHiddenFiles(_:)):
            (item as? NSMenuItem)?.state = Settings.shared.showHiddenFiles ? .on : .off
            return true
        default: return false
        }
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let event = NSApp.currentEvent
        let byMouse =
            event?.type == .rightMouseDown
            || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
        fillContextMenu(menu, onBlank: byMouse && outline.clickedRow < 0)
    }

    /// A right-click on blank space is about the archive, as in Finder: the selection lets go, so New
    /// Folder and Paste land at the top rather than inside something the person isn't pointing at.
    func fillContextMenu(_ menu: NSMenu, onBlank: Bool) {
        menu.removeAllItems()
        if onBlank { outline.deselectAll(nil) }
        let nodes = targets
        // The same symbols the menu bar gives these commands, so the two menus read as one.
        func add(_ title: String, _ action: Selector, _ symbol: String) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if nodes.isEmpty {
            add("Add Files…", #selector(addFiles(_:)), "doc.badge.plus")
            add("New Folder", #selector(newFolder(_:)), "folder.badge.plus")
            if NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                add("Paste", #selector(paste(_:)), "doc.on.clipboard")
            }
            return
        }
        let one = nodes.count == 1 ? "“\(nodes[0].name)”" : "\(nodes.count) Items"
        add("Open", #selector(openItems(_:)), "arrow.up.forward.app")
        if nodes.count == 1, let node = nodes.first, !node.isDirectory {
            let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWith.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
            openWith.submenu = openWithMenu(for: node.url)
            menu.addItem(openWith)
        }
        add("Quick Look \(one)", #selector(quickLookClicked(_:)), "eye")
        menu.addItem(.separator())
        add("Extract \(one)", #selector(extract(_:)), "square.and.arrow.down")
        add("Extract \(one) To…", #selector(extractTo(_:)), "folder")
        add("Copy", #selector(copy(_:)), "doc.on.doc")
        menu.addItem(.separator())
        if nodes.count == 1 { add("Rename", #selector(rename(_:)), "pencil") }
        add("New Folder", #selector(newFolder(_:)), "folder.badge.plus")
        menu.addItem(.separator())
        add("Delete", #selector(delete(_:)), "trash")
    }

    /// The default app first, then the rest by name, as in Finder.
    private func openWithMenu(for file: URL) -> NSMenu {
        let menu = NSMenu()
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: file)
        let others = NSWorkspace.shared.urlsForApplications(toOpen: file).filter { $0 != preferred }
            .sorted { Self.appName($0).localizedStandardCompare(Self.appName($1)) == .orderedAscending }
        for app in [preferred].compactMap({ $0 }) + others {
            let title = app == preferred ? "\(Self.appName(app)) (default)" : Self.appName(app)
            let item = menu.addItem(withTitle: title, action: #selector(openWith(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [app, file]
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            if app == preferred, !others.isEmpty { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        let other = menu.addItem(withTitle: "Other…", action: #selector(openWithOther(_:)), keyEquivalent: "")
        other.target = self
        other.representedObject = file
        return menu
    }

    private static func appName(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [URL], pair.count == 2 else { return }
        NSWorkspace.shared.open([pair[1]], withApplicationAt: pair[0], configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openWithOther(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? URL, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        panel.message = "Choose an app to open “\(file.lastPathComponent)”."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let app = panel.url else { return }
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func quickLookClicked(_ sender: Any?) {
        if let node = targets.first, !selection.contains(where: { $0 === node }) {
            outline.selectRowIndexes([outline.row(forItem: node)], byExtendingSelection: false)
        }
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    // MARK: Data source

    private func node(_ item: Any?) -> Node? { item as? Node ?? shown }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(item)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(item)!.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isDirectory == true
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key.flatMap(Node.SortKey.init)
        else { return }
        sortKey = key
        ascending = descriptor.ascending
        reload()
    }

    // MARK: Cells

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node, let id = tableColumn?.identifier else { return nil }
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        let field = cell.textField!
        switch id {
        case Self.nameColumn:
            field.stringValue = node.name
            cell.imageView?.image = icon(for: node)
        case Self.modifiedColumn:
            field.stringValue = node.modified.map(Self.listDate) ?? "--"
        case Self.sizeColumn:
            field.stringValue = formatSize(node.size)
        default:
            field.stringValue = node.kind
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        // Names keep both ends, where the extension and any numbering are; kinds and dates read from the start.
        field.lineBreakMode = id == Self.nameColumn ? .byTruncatingMiddle : .byTruncatingTail
        field.font = Theme.Font.body
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        ])
        if id == Self.nameColumn {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            field.isEditable = true
            field.target = self
            field.action = #selector(nameEdited(_:))
            field.delegate = self
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            ])
        } else {
            field.textColor = .secondaryLabelColor
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            if id == Self.sizeColumn {
                field.alignment = .right
                field.font = Theme.Font.digits
            }
        }
        return cell
    }

    /// The file's icon now, and for pictures, movies, and PDFs a thumbnail of the content once Quick
    /// Look has made one, as Finder's list shows.
    private func icon(for node: Node) -> NSImage {
        let key = "\(node.url.path)|\(node.modified?.timeIntervalSince1970 ?? 0)"
        if let thumbnail = thumbnails[key] { return thumbnail }
        let url = node.url
        let type = UTType(filenameExtension: url.pathExtension)
        if !node.isDirectory, let type, [.image, .movie, .pdf].contains(where: type.conforms(to:)),
            requested.insert(key).inserted
        {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 16, height: 16), scale: view.window?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                guard let image = thumbnail?.cgImage else { return }
                DispatchQueue.main.async { [weak self] in
                    // Fit within 16 points, keeping the picture's shape.
                    let scale = 16 / CGFloat(max(image.width, image.height, 1))
                    let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    self?.thumbnailArrived(NSImage(cgImage: image, size: size), key, url)
                }
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func thumbnailArrived(_ image: NSImage, _ key: String, _ url: URL) {
        thumbnails[key] = image
        let rows = outline.rows(in: outline.visibleRect)
        for row in rows.lowerBound..<rows.upperBound {
            guard (outline.item(atRow: row) as? Node)?.url == url,
                let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView
            else { continue }
            cell.imageView?.image = image
        }
    }

    /// One formatter for every row: making one per cell made scrolling a big archive stutter.
    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static func listDate(_ date: Date) -> String {
        listDateFormatter.string(from: date)
    }

    private func dropEnded() {
        cancelSpringLoad()
        highlightTopLevel(false)
        outline.draggingDestinationFeedbackStyle = .regular
    }

    /// Lights the archive's top level as a drop target: the empty list's drop area, or the whole
    /// list's edge once it has rows. The inspector uses it too, since its drops land there.
    func highlightTopLevel(_ on: Bool) {
        empty.highlighted = on && !empty.isHidden
        outline.rootDropGlow = on && empty.isHidden
    }

    func scheduleSpringLoad(for folder: Node?) {
        guard let folder, folder.isDirectory, !outline.isItemExpanded(folder) else {
            cancelSpringLoad()
            return
        }
        guard springLoadTargetPath != folder.path else { return }
        cancelSpringLoad()
        let path = folder.path
        springLoadTargetPath = path
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.springLoadTargetPath == path,
                    let target = self.shown?.find(path)
                else { return }
                self.outline.expandItem(target)
                self.springLoadTargetPath = nil
                self.springLoadWorkItem = nil
            }
        }
        springLoadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + springLoadDelay, execute: work)
    }

    func cancelSpringLoad() {
        springLoadWorkItem?.cancel()
        springLoadWorkItem = nil
        springLoadTargetPath = nil
    }

    /// Typing a name jumps to it, as in any Finder list.
    func outlineView(
        _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
    ) -> String? {
        tableColumn?.identifier == Self.nameColumn ? (item as? Node)?.name : nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        selectionChanged()
        view.window?.invalidateRestorableState()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        view.window?.invalidateRestorableState()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        view.window?.invalidateRestorableState()
    }

    // MARK: Dragging out

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node else { return nil }
        if FileManager.default.fileExists(atPath: node.url.path) {
            return node.url as NSURL
        }
        return filePromiseProvider(for: node)
    }

    func filePromiseProvider(for node: Node) -> NSFilePromiseProvider {
        let type: UTType =
            node.isDirectory
            ? .folder
            : (UTType(filenameExtension: node.url.pathExtension) ?? .data)
        let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
        provider.userInfo = node
        return provider
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? Node)?.name ?? "Item"
    }

    nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        OperationQueue()
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let node = filePromiseProvider.userInfo as? Node else {
            completionHandler(nil)
            return
        }
        do {
            if FileManager.default.fileExists(atPath: node.url.path) {
                try FileManager.default.copyItem(at: node.url, to: url)
            } else if node.isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data().write(to: url)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        dragged = draggedItems.compactMap { ($0 as? Node)?.path }
    }

    func outlineView(
        _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragged = []
    }

    // MARK: Dropping in

    func outlineView(
        _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard !Self.fileURLs(on: info.draggingPasteboard).isEmpty else { return [] }
        // Always onto a folder, never between rows: the list is sorted, so a position means nothing.
        var folder = item as? Node
        if let node = folder, !node.isDirectory { folder = node.parent }
        if folder?.path.isEmpty == true { folder = nil }
        outlineView.setDropItem(folder, dropChildIndex: NSOutlineViewDropOnItemIndex)
        scheduleSpringLoad(for: folder)

        let operation: NSDragOperation
        if info.draggingSource as? NSOutlineView === outline {
            let destination = folder?.path ?? ""
            let movable = dragged.contains { path in
                (path as NSString).deletingLastPathComponent != destination && destination != path
                    && !destination.hasPrefix(path + "/")
            }
            operation = movable ? .move : []
        } else {
            operation = .copy
        }
        // A drop on a folder lights its row; a drop on the archive itself lights the top level. A
        // drop that would be refused lights nothing, so the highlight never promises what won't happen.
        let onRoot = folder == nil
        outline.draggingDestinationFeedbackStyle = onRoot || operation.isEmpty ? .none : .regular
        highlightTopLevel(onRoot && !operation.isEmpty)
        return operation
    }

    func outlineView(
        _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int
    ) -> Bool {
        let folder = (item as? Node)?.path ?? ""
        if info.draggingSource as? NSOutlineView === outline {
            guard let document else { return false }
            let names = dragged.map { ($0 as NSString).lastPathComponent }
            do {
                try document.move(dragged, into: folder)
                reveal(names.map { folder.isEmpty ? $0 : "\(folder)/\($0)" })
            } catch {
                document.presentError(error)
            }
        } else {
            add(Self.fileURLs(on: info.draggingPasteboard), into: folder)
        }
        return true
    }

    // MARK: Quick Look

    @objc func toggleQuickLook(_ sender: Any?) {
        let panel = QLPreviewPanel.shared()!
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selection.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selection[index].url as NSURL
    }

    /// Arrow keys keep moving through the list while the panel has focus.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        outline.keyDown(with: event)
        return true
    }

    /// The panel zooms out of the row's icon and back into it.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let url = item.previewItemURL, let node = selection.first(where: { $0.url == url }),
            let window = view.window
        else { return .zero }
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
            let icon = cell.imageView, outline.visibleRect.intersects(outline.rect(ofRow: row))
        else { return .zero }
        return window.convertToScreen(icon.convert(icon.bounds, to: nil))
    }

    func previewPanel(
        _ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!
    ) -> Any! {
        item.previewItemURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// The keys Finder's list answers to: space for Quick Look, Return to rename, Command-Down to open,
/// and Delete to remove.
@MainActor
final class BrowserOutlineView: NSOutlineView {
    /// Hears when a drag leaves or finishes, so highlights can go.
    var onDragDone: (() -> Void)?

    /// An accent edge round the visible list while a drop would land in the archive's top level, the
    /// way Finder rings a window that a drop will go into.
    var rootDropGlow = false {
        didSet { if rootDropGlow != oldValue { setNeedsDisplay(visibleRect) } }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard rootDropGlow else { return }
        let edge = NSBezierPath(
            roundedRect: visibleRect.insetBy(dx: Theme.Space.xs, dy: Theme.Space.xs), xRadius: Theme.Radius.m,
            yRadius: Theme.Radius.m)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        edge.fill()
        NSColor.controlAccentColor.setStroke()
        edge.lineWidth = 2.5
        edge.stroke()
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDragDone?()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragDone?()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.keyCode, flags.subtracting([.numericPad, .function])) {
        case (49, []): NSApp.sendAction(#selector(BrowserViewController.toggleQuickLook(_:)), to: nil, from: self)
        case (36, []), (76, []): NSApp.sendAction(#selector(BrowserViewController.rename(_:)), to: nil, from: self)
        case (125, .command), (31, .command):
            NSApp.sendAction(#selector(BrowserViewController.openItems(_:)), to: nil, from: self)
        case (51, []), (117, []): NSApp.sendAction(#selector(BrowserViewController.delete(_:)), to: nil, from: self)
        default: super.keyDown(with: event)
        }
    }
}
