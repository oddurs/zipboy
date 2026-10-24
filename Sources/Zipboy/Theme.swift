import AppKit

/// Zipboy's look: the warm orange of its icon, rounded type for anything that speaks, and motion
/// only when the person hasn't asked for less.
@MainActor
enum Theme {
    /// The icon's orange, deeper in light mode so it holds up against white, lighter in dark mode.
    static let accent = NSColor(name: "ZipboyAccent") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.00, green: 0.62, blue: 0.27, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.40, blue: 0.05, alpha: 1)
    }

    /// Selected rows: a tint of the accent that keeps ordinary text readable on top.
    static let selection = NSColor(name: "ZipboySelection") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.00, green: 0.62, blue: 0.27, alpha: 0.26)
            : NSColor(srgbRed: 0.98, green: 0.55, blue: 0.16, alpha: 0.20)
    }

    static let dropFill = NSColor(name: "ZipboyDropFill") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.00, green: 0.62, blue: 0.27, alpha: 0.14)
            : NSColor(srgbRed: 0.91, green: 0.40, blue: 0.05, alpha: 0.10)
    }

    nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// SF Rounded: friendlier than the system font for headings, and still system type.
    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The edge of a capsule: both sides always, the top and bottom only where the shape ends there.
    static func outline(_ rect: NSRect, radius: CGFloat, closeTop: Bool, closeBottom: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let top = closeTop ? radius : 0, bottom = closeBottom ? radius : 0
        // Left side, from bottom to top, then across the top if it closes there.
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - bottom))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
        if closeTop {
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + top, y: rect.minY + top), radius: top, startAngle: 180,
                endAngle: 270)
            path.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - top, y: rect.minY + top), radius: top, startAngle: 270,
                endAngle: 0)
        } else {
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        }
        // Right side down, then across the bottom if it closes there.
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottom))
        if closeBottom {
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - bottom, y: rect.maxY - bottom), radius: bottom, startAngle: 0,
                endAngle: 90)
            path.line(to: NSPoint(x: rect.minX + bottom, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + bottom, y: rect.maxY - bottom), radius: bottom, startAngle: 90,
                endAngle: 180)
        }
        return path
    }

    /// The person's Reduce Motion setting. Tests replace it, rather than changing the Mac's own.
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A rounded rectangle whose top and bottom corners can be squared off, so neighbouring selected
    /// rows join into one shape.
    static func capsule(_ rect: NSRect, radius: CGFloat, roundTop: Bool, roundBottom: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let top = roundTop ? radius : 0, bottom = roundBottom ? radius : 0
        // AppKit's y runs up, but a flipped table view draws rows top-down; minY is the top.
        path.move(to: NSPoint(x: rect.minX + top, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - top, y: rect.minY + top), radius: top, startAngle: 270, endAngle: 0)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - bottom, y: rect.maxY - bottom), radius: bottom, startAngle: 0,
            endAngle: 90)
        path.line(to: NSPoint(x: rect.minX + bottom, y: rect.maxY))
        path.appendArc(
            withCenter: NSPoint(x: rect.minX + bottom, y: rect.maxY - bottom), radius: bottom, startAngle: 90,
            endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
        path.appendArc(
            withCenter: NSPoint(x: rect.minX + top, y: rect.minY + top), radius: top, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }
}

/// A list row that selects with a soft orange capsule instead of the system's solid blue bar.
final class ArchiveRowView: NSTableRowView {
    static let reuse = NSUserInterfaceItemIdentifier("ArchiveRow")

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 8, dy: 0)
        let shape = Theme.capsule(rect, radius: 7, roundTop: !isPreviousRowSelected, roundBottom: !isNextRowSelected)
        (isEmphasized ? Theme.selection : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        shape.fill()
        // A thin edge of the accent keeps the tint reading as orange on a dark background, not brown.
        // It runs down the sides only, closing at the first and last row, so joined rows read as one.
        guard isEmphasized else { return }
        Theme.accent.withAlphaComponent(0.45).setStroke()
        let edge = Theme.outline(
            rect.insetBy(dx: 0.5, dy: 0.5), radius: 6.5, closeTop: !isPreviousRowSelected,
            closeBottom: !isNextRowSelected)
        edge.lineWidth = 1
        edge.stroke()
    }

    /// Text stays its usual colour on the tint, rather than turning white as on the solid bar.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 9, dy: 1), xRadius: 7, yRadius: 7)
        Theme.dropFill.setFill()
        shape.fill()
        Theme.accent.setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }

    /// Dates, sizes, and kinds are secondary text, which drops under 4.5:1 on the tint; on a selected
    /// row they take the primary colour (13:1 in light, 7.5:1 in dark).
    override var isSelected: Bool {
        didSet { tintSecondaryText() }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        tintSecondaryText()
    }

    private func tintSecondaryText() {
        for case let cell as NSTableCellView in subviews where cell.identifier?.rawValue != "name" {
            cell.textField?.textColor = isSelected ? .labelColor : .secondaryLabelColor
        }
    }

    override var isPreviousRowSelected: Bool {
        didSet { needsDisplay = true }
    }

    override var isNextRowSelected: Bool {
        didSet { needsDisplay = true }
    }
}
