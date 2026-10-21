import AppKit

/// The menu bar, built in code because Command Line Tools can't compile a nib. Items without a target go
/// down the responder chain, which is how the document, window, and outline each pick up their own.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// `symbol` matches the icons AppKit gives its own items, so the app's sit alongside them.
    private static func item(
        _ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Zipboy")
        menu.addItem(item("About Zipboy", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = item("Services", nil)
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item("Hide Zipboy", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Zipboy", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Archive", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        // AppKit adds Open Recent here on its own.
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Add Files…", #selector(BrowserViewController.addFiles(_:)), "a", [.command, .shift],
                symbol: "doc.badge.plus"))
        menu.addItem(
            item(
                "New Folder", #selector(BrowserViewController.newFolder(_:)), "n", [.command, .shift],
                symbol: "folder.badge.plus"))
        menu.addItem(.separator())
        menu.addItem(item("Extract", #selector(BrowserViewController.extract(_:)), "e", symbol: "arrow.down.to.line"))
        menu.addItem(
            item(
                "Extract To…", #selector(BrowserViewController.extractTo(_:)), "e", [.command, .option],
                symbol: "folder"))
        menu.addItem(.separator())
        // The set an autosaving app has; AppKit turns Revert into the Revert To submenu with versions.
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert To", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Set Password…", #selector(ArchiveDocument.choosePassword(_:)), symbol: "lock"))
        menu.addItem(item("Remove Password", #selector(ArchiveDocument.removePassword(_:)), symbol: "lock.open"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:)), "\u{8}"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Rename", #selector(BrowserViewController.rename(_:)), symbol: "pencil"))
        menu.addItem(item("Find", #selector(ArchiveWindowController.focusSearch(_:)), "f"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Quick Look", #selector(BrowserViewController.toggleQuickLook(_:)), "y", symbol: "eye"))
        menu.addItem(
            item("Show Preview", #selector(NSSplitViewController.toggleInspector(_:)), "i", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(
            item("Expand All", #selector(BrowserViewController.expandAll(_:)), "\u{F703}", [.command, .option]))
        menu.addItem(
            item("Collapse All", #selector(BrowserViewController.collapseAll(_:)), "\u{F702}", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option]))
        menu.addItem(item("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
