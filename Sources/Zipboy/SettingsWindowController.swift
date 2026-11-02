import AppKit
import UniformTypeIdentifiers
import ZipboyKit

/// The Settings window (`⌘,`): a clean macOS form covering startup, browsing, extraction,
/// compression level, and default archive handling.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController(settings: .shared)

    let settings: Settings

    let launchPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let foldersFirstCheckbox = NSButton(
        checkboxWithTitle: "Keep folders on top when sorting", target: nil, action: nil)
    let autoExpandCheckbox = NSButton(
        checkboxWithTitle: "Automatically expand single-folder archives", target: nil, action: nil)
    let showHiddenCheckbox = NSButton(
        checkboxWithTitle: "Show hidden files (starting with a dot)", target: nil, action: nil)
    let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let wrapPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let revealCheckbox = NSButton(
        checkboxWithTitle: "Show extracted files in Finder", target: nil, action: nil)
    let updatesCheckbox = NSButton(
        checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    let compressionControl = NSSegmentedControl(
        labels: ["Faster", "Balanced", "Smaller"], trackingMode: .selectOne, target: nil, action: nil)
    let defaultStatusLabel = NSTextField(labelWithString: "")
    let makeDefaultZipButton = NSButton(title: "Set for ZIP", target: nil, action: nil)
    let makeDefaultAllButton = NSButton(title: "Set for All Archives", target: nil, action: nil)
    let restoreDefaultsButton = NSButton(title: "Restore Defaults", target: nil, action: nil)

    private var observer: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.title = "Zipboy Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
        buildUI(in: window)
        syncFromSettings()

        observer = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification, object: settings, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromSettings() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDefaultAppStatus() }
        }
    }

    required init?(coder: NSCoder) { fatalError("SettingsWindowController is built in code") }

    private func buildUI(in window: NSWindow) {
        let root = NSView()

        launchPopup.addItems(withTitles: [
            "Open a new empty archive",
            "Do nothing",
        ])
        launchPopup.target = self
        launchPopup.action = #selector(launchChanged(_:))

        for button in [foldersFirstCheckbox, autoExpandCheckbox, showHiddenCheckbox, revealCheckbox, updatesCheckbox] {
            button.target = self
            button.action = #selector(checkboxChanged(_:))
            button.font = .systemFont(ofSize: 13)
        }

        destinationPopup.addItems(withTitles: [
            "Next to the archive",
            "Downloads folder",
            "Ask every time",
        ])
        destinationPopup.target = self
        destinationPopup.action = #selector(destinationChanged(_:))

        wrapPopup.addItems(withTitles: [
            "When there are multiple items",
            "Always",
            "Never",
        ])
        wrapPopup.target = self
        wrapPopup.action = #selector(wrapChanged(_:))

        compressionControl.target = self
        compressionControl.action = #selector(compressionChanged(_:))
        compressionControl.segmentDistribution = .fillEqually

        let compressionCaption = Self.caption("Applies when saving or autosaving ZIP archives.")

        defaultStatusLabel.font = .systemFont(ofSize: 12)
        defaultStatusLabel.textColor = .secondaryLabelColor
        defaultStatusLabel.lineBreakMode = .byTruncatingMiddle

        makeDefaultZipButton.bezelStyle = .rounded
        makeDefaultZipButton.controlSize = .small
        makeDefaultZipButton.font = .systemFont(ofSize: 11)
        makeDefaultZipButton.target = self
        makeDefaultZipButton.action = #selector(makeDefaultForZip(_:))

        makeDefaultAllButton.bezelStyle = .rounded
        makeDefaultAllButton.controlSize = .small
        makeDefaultAllButton.font = .systemFont(ofSize: 11)
        makeDefaultAllButton.target = self
        makeDefaultAllButton.action = #selector(makeDefaultForAll(_:))

        let defaultButtons = NSStackView(views: [makeDefaultZipButton, makeDefaultAllButton])
        defaultButtons.orientation = .horizontal
        defaultButtons.spacing = 8

        let defaultStack = NSStackView(views: [defaultStatusLabel, defaultButtons])
        defaultStack.orientation = .vertical
        defaultStack.alignment = .leading
        defaultStack.spacing = 6

        let browsingStack = NSStackView(views: [
            foldersFirstCheckbox,
            autoExpandCheckbox,
            showHiddenCheckbox,
        ])
        browsingStack.orientation = .vertical
        browsingStack.alignment = .leading
        browsingStack.spacing = 8

        let compressionStack = NSStackView(views: [compressionControl, compressionCaption])
        compressionStack.orientation = .vertical
        compressionStack.alignment = .leading
        compressionStack.spacing = 5

        // The labels sit in their own grid cells, which VoiceOver doesn't tie to the controls beside them.
        launchPopup.setAccessibilityLabel("On launch")
        destinationPopup.setAccessibilityLabel("Extract to")
        wrapPopup.setAccessibilityLabel("Create folder")
        compressionControl.setAccessibilityLabel("Compression")

        let grid = NSGridView(views: [
            [Self.label("On Launch:"), launchPopup],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.label("Browsing:"), browsingStack],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.label("Extract To:"), destinationPopup],
            [Self.label("Create Folder:"), wrapPopup],
            [NSGridCell.emptyContentView, revealCheckbox],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.label("Compression:"), compressionStack],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.label("Default App:"), defaultStack],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.label("Updates:"), updatesCheckbox],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for rowIndex in [1, 3, 7, 9, 11] {
            grid.mergeCells(
                inHorizontalRange: NSRange(location: 0, length: 2),
                verticalRange: NSRange(location: rowIndex, length: 1))
            grid.row(at: rowIndex).topPadding = 4
            grid.row(at: rowIndex).bottomPadding = 4
            grid.row(at: rowIndex).rowAlignment = .none
        }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let footerDivider = Self.separator()
        footerDivider.translatesAutoresizingMaskIntoConstraints = false

        restoreDefaultsButton.bezelStyle = .rounded
        restoreDefaultsButton.target = self
        restoreDefaultsButton.action = #selector(restoreDefaults(_:))
        restoreDefaultsButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(grid)
        root.addSubview(footerDivider)
        root.addSubview(restoreDefaultsButton)

        NSLayoutConstraint.activate([
            launchPopup.widthAnchor.constraint(equalToConstant: 250),
            destinationPopup.widthAnchor.constraint(equalToConstant: 250),
            wrapPopup.widthAnchor.constraint(equalToConstant: 250),
            compressionControl.widthAnchor.constraint(equalToConstant: 250),

            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            footerDivider.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            restoreDefaultsButton.topAnchor.constraint(equalTo: footerDivider.bottomAnchor, constant: 12),
            restoreDefaultsButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            restoreDefaultsButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])

        window.contentView = root
        window.layoutIfNeeded()
        let fitting = root.fittingSize
        window.setContentSize(NSSize(width: max(480, fitting.width), height: fitting.height))
        window.center()
    }

    func syncFromSettings() {
        switch settings.launchBehavior {
        case .openEmptyArchive: launchPopup.selectItem(at: 0)
        case .doNothing: launchPopup.selectItem(at: 1)
        }
        foldersFirstCheckbox.state = settings.keepFoldersOnTop ? .on : .off
        autoExpandCheckbox.state = settings.autoExpandSingleFolder ? .on : .off
        showHiddenCheckbox.state = settings.showHiddenFiles ? .on : .off

        switch settings.extractDestination {
        case .archiveFolder: destinationPopup.selectItem(at: 0)
        case .downloads: destinationPopup.selectItem(at: 1)
        case .alwaysAsk: destinationPopup.selectItem(at: 2)
        }
        switch settings.wrapExtractedFiles {
        case .whenMultipleItems: wrapPopup.selectItem(at: 0)
        case .always: wrapPopup.selectItem(at: 1)
        case .never: wrapPopup.selectItem(at: 2)
        }
        revealCheckbox.state = settings.revealExtractedInFinder ? .on : .off
        updatesCheckbox.state = settings.checksForUpdates ? .on : .off

        switch settings.compressionLevel {
        case .fast: compressionControl.selectedSegment = 0
        case .balanced: compressionControl.selectedSegment = 1
        case .best: compressionControl.selectedSegment = 2
        }
        updateDefaultAppStatus()
    }

    private func updateDefaultAppStatus() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: .zip)
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.oddurs.zipboy"
        let handlerBundleID = handler.flatMap { Bundle(url: $0)?.bundleIdentifier }
        if handlerBundleID == myBundleID || handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            defaultStatusLabel.stringValue = "Zipboy is the default application for ZIP archives."
            makeDefaultZipButton.isEnabled = false
        } else if let handler {
            let name = FileManager.default.displayName(atPath: handler.path).replacingOccurrences(of: ".app", with: "")
            defaultStatusLabel.stringValue = "ZIP archives currently open with \(name)."
            makeDefaultZipButton.isEnabled = true
        } else {
            defaultStatusLabel.stringValue = "Choose which archives open with Zipboy in Finder."
            makeDefaultZipButton.isEnabled = true
        }
    }

    @objc private func launchChanged(_ sender: NSPopUpButton) {
        settings.launchBehavior = sender.indexOfSelectedItem == 0 ? .openEmptyArchive : .doNothing
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case foldersFirstCheckbox: settings.keepFoldersOnTop = on
        case autoExpandCheckbox: settings.autoExpandSingleFolder = on
        case showHiddenCheckbox: settings.showHiddenFiles = on
        case revealCheckbox: settings.revealExtractedInFinder = on
        case updatesCheckbox: settings.checksForUpdates = on
        default: break
        }
    }

    @objc private func destinationChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: settings.extractDestination = .downloads
        case 2: settings.extractDestination = .alwaysAsk
        default: settings.extractDestination = .archiveFolder
        }
    }

    @objc private func wrapChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: settings.wrapExtractedFiles = .always
        case 2: settings.wrapExtractedFiles = .never
        default: settings.wrapExtractedFiles = .whenMultipleItems
        }
    }

    @objc private func compressionChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: settings.compressionLevel = .fast
        case 2: settings.compressionLevel = .best
        default: settings.compressionLevel = .balanced
        }
    }

    @objc private func makeDefaultForZip(_ sender: Any?) {
        setDefaultApp(for: [.zip])
    }

    @objc private func makeDefaultForAll(_ sender: Any?) {
        let identifiers = [
            "public.zip-archive",
            "org.7-zip.7-zip-archive",
            "com.rarlab.rar-archive",
            "public.tar-archive",
            "org.gnu.gnu-zip-tar-archive",
            "org.gnu.gnu-zip-archive",
            "public.bzip2-archive",
            "org.tukaani.xz-archive",
            "com.github.facebook.zstd-archive",
        ]
        setDefaultApp(for: identifiers.compactMap(UTType.init))
    }

    private func setDefaultApp(for types: [UTType]) {
        let appURL = Bundle.main.bundleURL
        Task {
            for type in types {
                try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
            }
            updateDefaultAppStatus()
        }
    }

    @objc func restoreDefaults(_ sender: Any?) {
        settings.resetToDefaults()
    }

    private static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = .labelColor
        field.alignment = .right
        return field
    }

    private static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
