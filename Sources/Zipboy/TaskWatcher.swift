import AppKit
import UserNotifications

/// Long work across every window, shown where it can be seen from another app: a bar on the Dock
/// icon while it runs, and a notification when it finishes out of sight.
@MainActor
final class TaskWatcher: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskWatcher()

    /// Where finish notices go. Tests replace it; the system one needs a real app bundle.
    var notifier: any Notifier = SystemNotifier()
    /// Whether the person is looking at Zipboy, in which case its own window says it's done.
    var isFrontmost: () -> Bool = { NSApp.isActive }

    private var running: [LongTask] = []
    private var timer: Timer?
    let tile = DockTileProgress()

    func began(_ task: LongTask) {
        running.append(task)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func ended(_ task: LongTask, in document: ArchiveDocument) {
        running.removeAll { $0 === task }
        refresh()
        // Quick work, stopped work, and work watched from the window need no notice.
        guard !task.progress.isCancelled, Date().timeIntervalSince(task.started) >= 1, !isFrontmost() else { return }
        notifier.finished(
            task.title.replacingOccurrences(of: "…", with: ""), archive: document.displayName ?? "Archive")
    }

    /// Combined across every task, so two at once show one bar.
    var fraction: Double? {
        let total = running.reduce(Int64(0)) { $0 + $1.progress.totalUnitCount }
        guard !running.isEmpty, total > 0 else { return nil }
        return Double(running.reduce(Int64(0)) { $0 + $1.progress.completedUnitCount }) / Double(total)
    }

    func refresh() {
        tile.show(fraction)
        if running.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// A click on a finish notice brings that archive's window forward.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let name = response.notification.request.content.userInfo["archive"] as? String
        await MainActor.run { _ = Self.bringForward(archiveNamed: name) }
    }

    @discardableResult
    static func bringForward(archiveNamed name: String?) -> ArchiveDocument? {
        let document = NSDocumentController.shared.documents.compactMap { $0 as? ArchiveDocument }
            .first { $0.displayName == name }
        document?.showWindows()
        if document != nil { NSApp.activate() }
        return document
    }
}

/// Says that work finished, somewhere the person will see it.
@MainActor
protocol Notifier {
    func finished(_ what: String, archive: String)
}

/// Notification Center, or a bounce of the Dock icon if notifications are off. Outside an app bundle,
/// as when tests run, there is no Notification Center to ask, so it stays silent.
@MainActor
struct SystemNotifier: Notifier {
    func finished(_ what: String, archive: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = TaskWatcher.shared
        Task {
            let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard allowed else {
                NSApp.requestUserAttention(.informationalRequest)
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "\(what) finished"
            content.body = "“\(archive)” is ready."
            content.userInfo = ["archive": archive]
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// The Dock icon with a bar along its foot, as Finder and Safari draw one for copies and downloads.
@MainActor
final class DockTileProgress {
    private(set) var view: DockTileView?

    func show(_ fraction: Double?) {
        let tile = NSApp.dockTile
        guard let fraction else {
            view = nil
            tile.contentView = nil
            tile.display()
            return
        }
        if view == nil {
            let made = DockTileView(frame: NSRect(origin: .zero, size: tile.size))
            view = made
            tile.contentView = made
        }
        view?.fraction = fraction
        tile.display()
    }
}

final class DockTileView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let track = NSRect(
            x: bounds.width * 0.12, y: bounds.height * 0.1, width: bounds.width * 0.76, height: bounds.height * 0.09)
        let radius = track.height / 2
        NSColor(white: 0, alpha: 0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let inner = track.insetBy(dx: track.height * 0.15, dy: track.height * 0.15)
        var filled = inner
        filled.size.width = max(inner.height, inner.width * min(max(fraction, 0), 1))
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
    }
}
