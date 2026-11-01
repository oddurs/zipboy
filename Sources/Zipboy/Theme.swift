import AppKit

/// Zipboy's look: native macOS controls, system accent colors, and motion only when the person
/// hasn't asked for less.
@MainActor
enum Theme {
    /// The system's control accent color (blue by default, or whatever the person chose in System Settings).
    static var accent: NSColor { .controlAccentColor }

    /// A subtle wash of the system accent for active drop targets.
    static var dropFill: NSColor { .controlAccentColor.withAlphaComponent(0.08) }

    /// The person's Reduce Motion setting. Tests replace it, rather than changing the Mac's own.
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// A list row that uses standard macOS selection and draws a system-accent highlight when a folder
/// row is a drag destination.
final class ArchiveRowView: NSTableRowView {
    static let reuse = NSUserInterfaceItemIdentifier("ArchiveRow")

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6)
        Theme.dropFill.setFill()
        shape.fill()
        Theme.accent.setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }
}
