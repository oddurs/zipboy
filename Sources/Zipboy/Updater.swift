import AppKit
import OSLog
import ZipboyKit

/// Offers a newer Zipboy: once a day on its own, or when asked. It downloads the disk image, checks it
/// against the release's SHA-256, and opens it for the person to drag across. It never quits or
/// replaces the running app, so nothing unsaved is ever at risk; swapping itself in place waits for
/// a Developer ID signature to check against (0058).
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    enum Outcome: Equatable {
        case quiet
        case upToDate
        case offer(Updates.Release)
    }

    enum Failure: LocalizedError {
        case mismatch(String)
        var errorDescription: String? {
            switch self {
            case .mismatch(let version):
                "The download of Zipboy \(version) didn’t match its checksum, so it wasn’t opened. Try again, or download it from the release page."
            }
        }
    }

    /// Network and storage, replaced in tests.
    var fetch: (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    var defaults = UserDefaults.standard
    var settings = Settings.shared
    var localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private static let log = Logger(subsystem: "com.oddurs.zipboy", category: "updates")
    private enum Key {
        static let lastCheck = "updatesLastCheck"
        static let offered = "updatesOfferedVersion"
    }

    /// What a check finds. An automatic one runs at most daily, stays quiet when there's nothing new,
    /// and offers each version once; one from the menu always answers.
    func check(manual: Bool, now: Date = Date()) async -> Outcome {
        if !manual {
            guard settings.checksForUpdates else { return .quiet }
            if let last = defaults.object(forKey: Key.lastCheck) as? Date, now.timeIntervalSince(last) < 86_400 {
                return .quiet
            }
        }
        defaults.set(now, forKey: Key.lastCheck)
        guard let data = try? await fetch(Updates.feed), let release = Updates.release(from: data),
            Updates.isNewer(release.version, than: localVersion)
        else { return manual ? .upToDate : .quiet }
        if !manual, defaults.string(forKey: Key.offered) == release.version { return .quiet }
        defaults.set(release.version, forKey: Key.offered)
        return .offer(release)
    }

    /// Downloads the release's disk image into Caches and checks it. A mismatch is refused and logged.
    func download(_ release: Updates.Release) async throws -> URL {
        let folder = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Zipboy Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = folder.appendingPathComponent(release.disk.lastPathComponent)
        try? FileManager.default.removeItem(at: disk)
        try await fetch(release.disk).write(to: disk)
        let sum = String(decoding: try await fetch(release.checksum), as: UTF8.self)
        guard Updates.matches(disk, checksumFile: sum) else {
            try? FileManager.default.removeItem(at: disk)
            Self.log.error("refused Zipboy \(release.version, privacy: .public): checksum mismatch")
            throw Failure.mismatch(release.version)
        }
        return disk
    }

    /// Launch's daily look.
    func checkIfDue() {
        Task { await respond(to: await check(manual: false), manual: false) }
    }

    @objc func checkNow(_ sender: Any?) {
        Task { await respond(to: await check(manual: true), manual: true) }
    }

    private func respond(to outcome: Outcome, manual: Bool) async {
        let alert = NSAlert()
        switch outcome {
        case .quiet:
            return
        case .upToDate:
            alert.messageText = "Zipboy is up to date"
            alert.informativeText = "Version \(localVersion) is the newest."
            alert.runModal()
        case .offer(let release):
            alert.messageText = "Zipboy \(release.version) is available"
            alert.informativeText =
                "You have \(localVersion). It downloads as a disk image to drag into Applications, whenever suits you."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Release Notes")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do {
                    NSWorkspace.shared.open(try await download(release))
                } catch {
                    NSApp.presentError(error)
                }
            case .alertThirdButtonReturn:
                NSWorkspace.shared.open(release.page)
            default:
                break
            }
        }
    }
}
