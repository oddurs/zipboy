import Foundation

/// User preferences and sensible defaults for Zipboy, backed by `UserDefaults`.
public final class Settings: @unchecked Sendable {
    public static let shared = Settings()
    public static let didChangeNotification = Notification.Name("ZipboySettingsDidChange")

    /// What happens when Zipboy is launched without opening a specific file.
    public enum LaunchBehavior: String, CaseIterable, Sendable {
        case openEmptyArchive
        case doNothing
    }

    /// Where one-click Extract (`⌘E` or toolbar Extract) places extracted files.
    public enum ExtractDestination: String, CaseIterable, Sendable {
        case archiveFolder
        case downloads
        case alwaysAsk
    }

    /// When extracting a whole archive creates a surrounding folder named after the archive.
    public enum WrapBehavior: String, CaseIterable, Sendable {
        case whenMultipleItems
        case always
        case never
    }

    /// Deflate compression effort when writing or autosaving a `.zip` archive.
    public enum CompressionLevel: Int, CaseIterable, Sendable {
        case fast = 1
        case balanced = 6
        case best = 9
    }

    private enum Key {
        static let launchBehavior = "launchBehavior"
        static let keepFoldersOnTop = "keepFoldersOnTop"
        static let autoExpandSingleFolder = "autoExpandSingleFolder"
        static let showHiddenFiles = "showHiddenFiles"
        static let extractDestination = "extractDestination"
        static let wrapExtractedFiles = "wrapExtractedFiles"
        static let revealExtractedInFinder = "revealExtractedInFinder"
        static let compressionLevel = "compressionLevel"

        static let all = [
            launchBehavior,
            keepFoldersOnTop,
            autoExpandSingleFolder,
            showHiddenFiles,
            extractDestination,
            wrapExtractedFiles,
            revealExtractedInFinder,
            compressionLevel,
        ]
    }

    public static var defaultValues: [String: Any] {
        [
            Key.launchBehavior: LaunchBehavior.openEmptyArchive.rawValue,
            Key.keepFoldersOnTop: true,
            Key.autoExpandSingleFolder: true,
            Key.showHiddenFiles: false,
            Key.extractDestination: ExtractDestination.archiveFolder.rawValue,
            Key.wrapExtractedFiles: WrapBehavior.whenMultipleItems.rawValue,
            Key.revealExtractedInFinder: true,
            Key.compressionLevel: CompressionLevel.balanced.rawValue,
        ]
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultValues)
    }

    public var launchBehavior: LaunchBehavior {
        get {
            defaults.string(forKey: Key.launchBehavior).flatMap(LaunchBehavior.init(rawValue:))
                ?? .openEmptyArchive
        }
        set {
            guard newValue != launchBehavior else { return }
            defaults.set(newValue.rawValue, forKey: Key.launchBehavior)
            notify()
        }
    }

    public var keepFoldersOnTop: Bool {
        get { defaults.bool(forKey: Key.keepFoldersOnTop) }
        set {
            guard newValue != keepFoldersOnTop else { return }
            defaults.set(newValue, forKey: Key.keepFoldersOnTop)
            notify()
        }
    }

    public var autoExpandSingleFolder: Bool {
        get { defaults.bool(forKey: Key.autoExpandSingleFolder) }
        set {
            guard newValue != autoExpandSingleFolder else { return }
            defaults.set(newValue, forKey: Key.autoExpandSingleFolder)
            notify()
        }
    }

    public var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set {
            guard newValue != showHiddenFiles else { return }
            defaults.set(newValue, forKey: Key.showHiddenFiles)
            notify()
        }
    }

    public var extractDestination: ExtractDestination {
        get {
            defaults.string(forKey: Key.extractDestination).flatMap(ExtractDestination.init(rawValue:))
                ?? .archiveFolder
        }
        set {
            guard newValue != extractDestination else { return }
            defaults.set(newValue.rawValue, forKey: Key.extractDestination)
            notify()
        }
    }

    public var wrapExtractedFiles: WrapBehavior {
        get {
            defaults.string(forKey: Key.wrapExtractedFiles).flatMap(WrapBehavior.init(rawValue:))
                ?? .whenMultipleItems
        }
        set {
            guard newValue != wrapExtractedFiles else { return }
            defaults.set(newValue.rawValue, forKey: Key.wrapExtractedFiles)
            notify()
        }
    }

    public var revealExtractedInFinder: Bool {
        get { defaults.bool(forKey: Key.revealExtractedInFinder) }
        set {
            guard newValue != revealExtractedInFinder else { return }
            defaults.set(newValue, forKey: Key.revealExtractedInFinder)
            notify()
        }
    }

    public var compressionLevel: CompressionLevel {
        get {
            CompressionLevel(rawValue: defaults.integer(forKey: Key.compressionLevel)) ?? .balanced
        }
        set {
            guard newValue != compressionLevel else { return }
            defaults.set(newValue.rawValue, forKey: Key.compressionLevel)
            notify()
        }
    }

    /// Restores every setting to its sensible default and notifies observers.
    public func resetToDefaults() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        defaults.register(defaults: Self.defaultValues)
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
