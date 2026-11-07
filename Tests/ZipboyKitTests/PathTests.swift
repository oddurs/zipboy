import Foundation
import Testing
import ZipboyKit

@Suite struct EntryPathTests {
    @Test func keepsOrdinaryPaths() {
        #expect(EntryPath.sanitized("docs/read me.txt") == "docs/read me.txt")
        #expect(EntryPath.sanitized("./a/./b/") == "a/b")
        #expect(EntryPath.sanitized("win\\style\\path.txt") == "win/style/path.txt")
    }

    @Test func rootsAbsolutePathsInsideTheArchive() {
        #expect(EntryPath.sanitized("/etc/passwd") == "etc/passwd")
    }

    @Test func refusesToClimbOut() {
        #expect(EntryPath.sanitized("../evil") == nil)
        #expect(EntryPath.sanitized("a/../../evil") == nil)
        #expect(EntryPath.sanitized("a\\..\\..\\evil") == nil)
        #expect(EntryPath.sanitized("") == nil)
        #expect(EntryPath.sanitized("./") == nil)
    }

    @Test func dropsFinderMetadata() {
        #expect(EntryPath.sanitized("__MACOSX/a/._b.txt") == nil)
        #expect(EntryPath.sanitized("a/.DS_Store") == nil)
        #expect(EntryPath.sanitized("a/._b.txt") == nil)
        #expect(EntryPath.sanitized("a/.hidden") == "a/.hidden")
    }

    @Test func allowsLinksThatStayInside() {
        #expect(EntryPath.linkStaysInside(path: "App/Current", target: "Versions/A"))
        #expect(EntryPath.linkStaysInside(path: "a/b/link", target: "../../c"))
    }

    @Test func refusesLinksThatLeave() {
        #expect(!EntryPath.linkStaysInside(path: "link", target: "/etc"))
        #expect(!EntryPath.linkStaysInside(path: "link", target: ".."))
        #expect(!EntryPath.linkStaysInside(path: "a/link", target: "../../x"))
    }
}

@Suite struct NamingTests {
    @Test func keepsAFreeName() {
        #expect(Naming.unique("a.txt", isDirectory: false, taken: ["b.txt"]) == "a.txt")
    }

    @Test func numbersLikeFinder() {
        #expect(Naming.unique("photo.jpg", isDirectory: false, taken: ["photo.jpg"]) == "photo 2.jpg")
        #expect(Naming.unique("photo.jpg", isDirectory: false, taken: ["photo.jpg", "photo 2.jpg"]) == "photo 3.jpg")
        #expect(Naming.unique("photo 2.jpg", isDirectory: false, taken: ["photo 2.jpg"]) == "photo 3.jpg")
    }

    @Test func ignoresCaseAsAPFSDoes() {
        #expect(Naming.unique("A.txt", isDirectory: false, taken: ["a.txt"]) == "A 2.txt")
    }

    @Test func numbersFoldersWithoutSplittingAnExtension() {
        #expect(Naming.unique("v1.2", isDirectory: true, taken: ["v1.2"]) == "v1.2 2")
        #expect(Naming.unique("Makefile", isDirectory: false, taken: ["Makefile"]) == "Makefile 2")
    }

    @Test func stripsCompoundArchiveExtensions() {
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/project.tar.gz")) == "project")
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/backup.tar.xz")) == "backup")
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/data.tar.zst")) == "data")
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/initrd.cpio.gz")) == "initrd")
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/disc.iso.gz")) == "disc")
        #expect(Naming.stem(of: URL(fileURLWithPath: "/tmp/plain.rar")) == "plain")
    }
}

@Suite struct ZipMethodTests {
    @Test func storesWhatIsAlreadyCompressed() {
        #expect(ZipMethod.forFile(named: "IMG_0001.JPG") == .store)
        #expect(ZipMethod.forFile(named: "inner.zip") == .store)
        #expect(ZipMethod.forFile(named: "bundle.tbz2") == .store)
        #expect(ZipMethod.forFile(named: "release.txz") == .store)
        #expect(ZipMethod.forFile(named: "package.deb") == .store)
        #expect(ZipMethod.forFile(named: "archive.cpgz") == .store)
        #expect(ZipMethod.forFile(named: "notes.txt") == .deflate)
        #expect(ZipMethod.forFile(named: "README") == .deflate)
    }

    @Test func recognizesBroadArchiveExtensions() {
        for ext in [
            "zip", "zipx", "rar", "7z", "tar", "tgz", "tbz2", "txz", "tlz", "taz", "cpgz", "xar", "cab", "lha",
            "deb",
        ] {
            #expect(ZipMethod.archiveExtensions.contains(ext), "\(ext)")
        }
        for unsupported in ["zst", "tzst", "lz4", "lzo"] {
            #expect(!ZipMethod.archiveExtensions.contains(unsupported), "\(unsupported)")
        }
    }
}

@Suite struct SettingsTests {
    func isolatedSettings() -> (Settings, String) {
        let suiteName = "com.oddurs.zipboy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (Settings(defaults: defaults), suiteName)
    }

    @Test func registersSensibleDefaultsAndRestoresThem() {
        let (settings, suiteName) = isolatedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        #expect(settings.launchBehavior == .openEmptyArchive)
        #expect(settings.keepFoldersOnTop == true)
        #expect(settings.autoExpandSingleFolder == true)
        #expect(settings.showHiddenFiles == false)
        #expect(settings.extractDestination == .archiveFolder)
        #expect(settings.wrapExtractedFiles == .whenMultipleItems)
        #expect(settings.revealExtractedInFinder == true)
        #expect(settings.compressionLevel == .balanced)

        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let notifications = Counter()
        let token = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification, object: settings, queue: nil
        ) { _ in
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.launchBehavior = .doNothing
        settings.keepFoldersOnTop = false
        settings.autoExpandSingleFolder = false
        settings.showHiddenFiles = true
        settings.extractDestination = .downloads
        settings.wrapExtractedFiles = .always
        settings.revealExtractedInFinder = false
        settings.compressionLevel = .best

        #expect(settings.launchBehavior == .doNothing)
        #expect(settings.keepFoldersOnTop == false)
        #expect(settings.autoExpandSingleFolder == false)
        #expect(settings.showHiddenFiles == true)
        #expect(settings.extractDestination == .downloads)
        #expect(settings.wrapExtractedFiles == .always)
        #expect(settings.revealExtractedInFinder == false)
        #expect(settings.compressionLevel == .best)
        #expect(notifications.count == 8)

        settings.resetToDefaults()
        #expect(settings.launchBehavior == .openEmptyArchive)
        #expect(settings.keepFoldersOnTop == true)
        #expect(settings.autoExpandSingleFolder == true)
        #expect(settings.showHiddenFiles == false)
        #expect(settings.extractDestination == .archiveFolder)
        #expect(settings.wrapExtractedFiles == .whenMultipleItems)
        #expect(settings.revealExtractedInFinder == true)
        #expect(settings.compressionLevel == .balanced)
        #expect(notifications.count == 9)
    }
}
