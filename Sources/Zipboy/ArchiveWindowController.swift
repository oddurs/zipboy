import AppKit
import ZipboyKit

/// One archive's window: the file list, a preview inspector beside it, and a unified toolbar.
@MainActor
final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSSharingServicePickerToolbarItemDelegate
{
    let browser = BrowserViewController()
    private let preview = PreviewViewController()
    private let split = InspectorSplitViewController()
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .search)
    /// Long work's bar and stop button, under the toolbar while it runs.
    let taskBar = NSTitlebarAccessoryViewController()
    private let strip = TaskStrip()
    private var taskTimer: Timer?

    init(document: ArchiveDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.minSize = NSSize(width: 560, height: 320)
        window.toolbarStyle = .unified
        // Tabs follow the person's "Prefer tabs" setting, as every document app's do.
        window.tabbingMode = .automatic
        super.init(window: window)
        window.delegate = self

        browser.document = document
        browser.onSelectionChange = { [weak self] nodes in self?.selectionChanged(nodes) }
        preview.onDropHover = { [weak self] in self?.browser.highlightTopLevel($0) }
        preview.onDrop = { [weak self] in self?.browser.add($0, into: "") }

        let list = NSSplitViewItem(viewController: browser)
        list.minimumThickness = 320
        let inspector = NSSplitViewItem(inspectorWithViewController: preview)
        inspector.minimumThickness = 240
        inspector.maximumThickness = 520
        inspector.preferredThicknessFraction = 0.32
        split.splitViewItems = [list, inspector]
        split.splitView.autosaveName = "ArchiveSplit"
        window.contentViewController = split

        let toolbar = NSToolbar(identifier: "ArchiveToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar

        searchItem.searchField.placeholderString = "Search"
        searchItem.searchField.target = self
        searchItem.searchField.action = #selector(searchChanged(_:))
        searchItem.searchField.sendsSearchStringImmediately = true

        taskBar.view = strip
        taskBar.layoutAttribute = .bottom
        taskBar.isHidden = true
        window.addTitlebarAccessoryViewController(taskBar)

        window.setContentSize(NSSize(width: 980, height: 620))
        Self.cascade(window)
        window.initialFirstResponder = browser.outline

        document.onChange = { [weak self] in self?.refresh() }
        document.onStatus = { [weak self] in self?.updateStatus() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("ArchiveWindowController is built in code") }

    /// Where the next window's top left goes. AppKit cascades only windows that come from a nib.
    private static var cascadePoint: NSPoint?

    private static func cascade(_ window: NSWindow) {
        if let point = cascadePoint,
            NSApp.windows.contains(where: { $0.isVisible && $0.windowController is ArchiveWindowController })
        {
            cascadePoint = window.cascadeTopLeft(from: point)
        } else {
            window.center()
            cascadePoint = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
        }
    }

    /// Not `document`, which AppKit sets only after init, when the first refresh has already run.
    private var archive: ArchiveDocument? { browser.document }

    private func refresh() {
        browser.reload()
        updateStatus()
    }

    /// The subtitle, and the inspector when it describes the archive. Cheap, for progress ticks.
    private func updateStatus() {
        guard let archive else { return }
        if !archive.tasks.isEmpty, taskTimer == nil {
            taskTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.showTask() }
            }
        }
        if browser.selection.isEmpty { preview.show([], archive: archive) }
        if let activity = archive.activity {
            window?.subtitle = activity
            return
        }
        // What's in it, not what it's made of: the format only matters when it isn't a ZIP, and the
        // inspector says so.
        var parts: [String] = []
        if let tree = archive.tree, tree.descendantCount > 0 {
            let count = tree.descendantCount
            parts.append(count == 1 ? "1 item" : "\(count.formatted()) items")
            parts.append(formatSize(tree.size))
        } else if archive.tree != nil {
            parts.append("Empty")
        }
        if archive.password != nil { parts.append("Password Protected") }
        window?.subtitle = parts.joined(separator: " · ")
    }

    private func selectionChanged(_ nodes: [Node]) {
        guard let archive else { return }
        preview.show(nodes, archive: archive)
    }

    /// Brings up the bar once work has run a second, so quick work never flickers it, and puts it
    /// away when the last task ends.
    func showTask(now: Date = Date()) {
        guard let task = archive?.tasks.last else {
            taskBar.isHidden = true
            taskTimer?.invalidate()
            taskTimer = nil
            return
        }
        guard now.timeIntervalSince(task.started) >= 1 else { return }
        strip.show(task)
        taskBar.isHidden = false
    }

    /// Escape stops long work, as it stops a copy in Finder.
    override func cancelOperation(_ sender: Any?) {
        archive?.stopTask(sender)
    }

    @objc func searchChanged(_ sender: NSSearchField) {
        browser.filter(sender.stringValue)
        window?.invalidateRestorableState()
    }

    // MARK: Restoring

    private enum Key {
        static let expanded = "ZipboyExpanded"
        static let selected = "ZipboySelected"
        static let query = "ZipboyQuery"
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        let saved = browser.savedState
        state.encode(saved.expanded as NSArray, forKey: Key.expanded)
        state.encode(saved.selected as NSArray, forKey: Key.selected)
        state.encode(saved.query as NSString, forKey: Key.query)
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        let saved = BrowserViewController.SavedState(
            expanded: state.decodeArrayOfObjects(ofClass: NSString.self, forKey: Key.expanded) as? [String] ?? [],
            selected: state.decodeArrayOfObjects(ofClass: NSString.self, forKey: Key.selected) as? [String] ?? [],
            query: state.decodeObject(of: NSString.self, forKey: Key.query) as String? ?? "")
        searchItem.searchField.stringValue = saved.query
        browser.restore(saved)
    }

    @objc func focusSearch(_ sender: Any?) {
        searchItem.beginSearchInteraction()
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .add, .flexibleSpace, .extract, .share, .search, .inspectorTrackingSeparator,
            .flexibleSpace,
            .toggleInspector,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.newFolder, .quickLook, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .add:
            button(identifier, "Add", "plus", "Add files to the archive", #selector(BrowserViewController.addFiles(_:)))
        case .newFolder:
            button(
                identifier, "New Folder", "folder.badge.plus", "Make a new folder",
                #selector(BrowserViewController.newFolder(_:)))
        case .extract:
            button(
                identifier, "Extract", "square.and.arrow.down", "Extract the selected items, or everything",
                #selector(BrowserViewController.extract(_:)))
        case .quickLook:
            button(
                identifier, "Quick Look", "eye", "Quick Look the selected items",
                #selector(BrowserViewController.toggleQuickLook(_:)))
        case .search:
            searchItem
        case .share:
            {
                let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
                item.delegate = self
                item.toolTip = "Share the selected items, or the archive"
                return item
            }()
        default:
            nil
        }
    }

    /// The selection, or with nothing selected the archive file itself.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        let selected = browser.selection.map(\.url)
        if !selected.isEmpty { return selected }
        return archive?.source.map { [$0] } ?? []
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.action = action
        return item
    }
}

/// One line under the toolbar: what is happening, how far it has got, and a button to stop it.
@MainActor
final class TaskStrip: NSView {
    let label = NSTextField(labelWithString: "")
    let bar = NSProgressIndicator()
    let stop = NSButton(
        image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Stop")!, target: nil,
        action: #selector(ArchiveDocument.stopTask(_:)))

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Theme.Font.callout
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.style = .bar
        bar.controlSize = .small
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        stop.isBordered = false
        stop.contentTintColor = .secondaryLabelColor
        stop.toolTip = "Stop (Esc)"
        let row = NSStackView(views: [label, bar, stop])
        row.spacing = Theme.Space.s
        row.edgeInsets = NSEdgeInsets(top: 0, left: Theme.Space.l, bottom: 0, right: Theme.Space.m)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 160),
        ])
    }

    required init?(coder: NSCoder) { fatalError("TaskStrip is built in code") }

    func show(_ task: LongTask) {
        label.stringValue = task.title
        bar.doubleValue = task.progress.fractionCompleted
        bar.setAccessibilityValue("\(Int(task.progress.fractionCompleted * 100)) percent")
    }
}

/// The list and its inspector. The menu names the toggle for what it will do, as Finder's does,
/// rather than always offering to show an inspector that is already open.
@MainActor
final class InspectorSplitViewController: NSSplitViewController {
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleInspector(_:)), let menuItem = item as? NSMenuItem,
            let inspector = splitViewItems.last
        {
            menuItem.title = inspector.isCollapsed ? "Show Inspector" : "Hide Inspector"
        }
        return super.validateUserInterfaceItem(item)
    }
}

extension NSToolbarItem.Identifier {
    static let add = Self("add")
    static let newFolder = Self("newFolder")
    static let extract = Self("extract")
    static let quickLook = Self("quickLook")
    static let search = Self("search")
    static let share = Self("share")
}
