import AppKit
import ZipboyKit

/// One archive's window: the file list, a preview inspector beside it, and a unified toolbar.
@MainActor
final class ArchiveWindowController: NSWindowController, NSToolbarDelegate,
    NSSharingServicePickerToolbarItemDelegate
{
    private let browser = BrowserViewController()
    private let preview = PreviewViewController()
    private let split = NSSplitViewController()
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .search)

    init(document: ArchiveDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.minSize = NSSize(width: 560, height: 320)
        window.toolbarStyle = .unified
        super.init(window: window)

        browser.document = document
        browser.onSelectionChange = { [weak self] nodes in self?.selectionChanged(nodes) }

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

    @objc func searchChanged(_ sender: NSSearchField) {
        browser.filter(sender.stringValue)
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
                identifier, "Extract", "arrow.down.to.line", "Extract next to the archive",
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

extension NSToolbarItem.Identifier {
    static let add = Self("add")
    static let newFolder = Self("newFolder")
    static let extract = Self("extract")
    static let quickLook = Self("quickLook")
    static let search = Self("search")
    static let share = Self("share")
}
