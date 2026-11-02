import AppKit

/// Zipboy's design system: one brand colour, neon green, on an otherwise native Mac window. Views take
/// colours, spacing, radii, and type from here, never as literals, so the look stays one look.
@MainActor
enum Theme {
    // MARK: Colour

    /// Neon green as a fill: selection tints, the primary button, progress. Slightly deeper in light
    /// mode so it holds its shape against white. Text on it uses `ink`, never white.
    static let neon = NSColor(name: "ZipboyNeon") { appearance in
        isDark(appearance) ? rgb(0x39FF6E) : rgb(0x2EE85F)
    }

    /// Neon green where it has to read against the window: strokes, glyphs, and text. Raw neon is only
    /// 1.6:1 on white, so light mode takes a deep green (5.5:1).
    static let accent = NSColor(name: "ZipboyAccent") { appearance in
        isDark(appearance) ? rgb(0x39FF6E) : rgb(0x0B7A30)
    }

    /// Text and symbols on a neon fill: 8.9:1 on the light fill, 10.9:1 on the dark one.
    static let ink = NSColor(name: "ZipboyInk") { _ in rgb(0x06301A) }

    /// Selected rows: a wash of neon light enough that ordinary text keeps its contrast on top.
    static let selection = NSColor(name: "ZipboySelection") { appearance in
        isDark(appearance) ? rgb(0x39FF6E, alpha: 0.22) : rgb(0x2EE85F, alpha: 0.30)
    }

    /// The selection's edge, which keeps the tint reading as green rather than grey on dark.
    static let selectionEdge = NSColor(name: "ZipboySelectionEdge") { appearance in
        isDark(appearance) ? rgb(0x39FF6E, alpha: 0.45) : rgb(0x0B7A30, alpha: 0.30)
    }

    /// Where a drop would land.
    static let dropFill = NSColor(name: "ZipboyDropFill") { appearance in
        isDark(appearance) ? rgb(0x39FF6E, alpha: 0.12) : rgb(0x2EE85F, alpha: 0.16)
    }

    /// Recessed surfaces such as the preview well: a step off the window, in either appearance.
    static let well = NSColor(name: "ZipboyWell") { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.045) : NSColor(white: 0, alpha: 0.035)
    }

    /// Quiet controls and pills: a translucent step off whatever they sit on. Explicit values, because
    /// the system fills resolve to opaque black when a layer asks for them.
    static let quiet = NSColor(name: "ZipboyQuiet") { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.06)
    }

    nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    nonisolated private static func rgb(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // MARK: Space, shape, and type

    /// A 4-point scale. Gaps between related things are small; between groups, large.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Corner radii, drawn with continuous corners as the system's own are.
    enum Radius {
        /// Rows and small controls.
        static let s: CGFloat = 6
        /// Buttons and cards.
        static let m: CGFloat = 10
        /// Wells and trays.
        static let l: CGFloat = 14
    }

    /// The type ramp. Headings are SF Rounded, which echoes the icon and is still system type; reading
    /// text stays SF Pro.
    enum Font {
        static var title: NSFont { rounded(15, .semibold) }
        static var heading: NSFont { rounded(16, .semibold) }
        static var body: NSFont { .systemFont(ofSize: 13) }
        static var callout: NSFont { .systemFont(ofSize: 12) }
        static var label: NSFont { .systemFont(ofSize: 11, weight: .medium) }
        static var digits: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }
        static var code: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
        static var button: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    }

    nonisolated static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: Motion

    /// The person's Reduce Motion setting. Tests replace it, rather than changing the Mac's own.
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Native controls

    /// macOS's palette index for green, the nearest system accent to neon.
    nonisolated static let systemGreen = 3

    /// Gives checkboxes, switches, focus rings, and default buttons the brand green, but only while
    /// the person uses Multicolor: an accent they chose themselves wins, as with any app's accent
    /// colour. Registered defaults sit below the person's own, so nothing is written.
    nonisolated static func registerAccent() {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        UserDefaults.standard.register(defaults: accentDefaults(over: global))
    }

    /// What `registerAccent` registers, given the person's global preferences.
    nonisolated static func accentDefaults(over global: [String: Any]) -> [String: Any] {
        guard global["AppleAccentColor"] == nil else { return [:] }
        var registered: [String: Any] = ["AppleAccentColor": systemGreen]
        if global["AppleHighlightColor"] == nil {
            registered["AppleHighlightColor"] = "0.752941 0.964706 0.678431 Green"
        }
        return registered
    }

    // MARK: Shapes

    /// A rounded rectangle whose top and bottom corners can be squared off, so neighbouring selected
    /// rows join into one shape. Rows are flipped: minY is the top.
    static func capsule(_ rect: NSRect, radius: CGFloat, roundTop: Bool, roundBottom: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let top = roundTop ? radius : 0
        let bottom = roundBottom ? radius : 0
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

    /// The outline of `capsule`, open where a neighbouring row continues the shape: both sides always,
    /// the top and bottom only where the selection starts and ends.
    static func edge(_ rect: NSRect, radius: CGFloat, closeTop: Bool, closeBottom: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let top = closeTop ? radius : 0
        let bottom = closeBottom ? radius : 0
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - bottom))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
        if closeTop {
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + top, y: rect.minY + top), radius: top, startAngle: 180,
                endAngle: 270)
            path.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - top, y: rect.minY + top), radius: top, startAngle: 270, endAngle: 0)
        } else {
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        }
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

    /// Resolves a dynamic colour for a layer, which can't follow appearance changes on its own.
    static func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

/// A list row that selects with a neon-tinted capsule, inset from the edges and joined across
/// neighbouring rows, instead of the system's solid bar.
final class ArchiveRowView: NSTableRowView {
    static let reuse = NSUserInterfaceItemIdentifier("ArchiveRow")

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Theme.Space.s, dy: 0)
        let joinedAbove = isPreviousRowSelected
        let joinedBelow = isNextRowSelected
        let shape = Theme.capsule(
            rect, radius: Theme.Radius.s, roundTop: !joinedAbove, roundBottom: !joinedBelow)
        (isEmphasized ? Theme.selection : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        shape.fill()
        guard isEmphasized else { return }
        // The edge runs down both sides, closing only where the selection starts and ends.
        Theme.selectionEdge.setStroke()
        Theme.edge(
            rect.insetBy(dx: 0.5, dy: 0.5), radius: Theme.Radius.s - 0.5, closeTop: !joinedAbove,
            closeBottom: !joinedBelow
        ).stroke()
    }

    /// Text stays its usual colour on the tint, rather than turning white as on the solid bar.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Theme.Space.s, dy: 1), xRadius: Theme.Radius.s, yRadius: Theme.Radius.s)
        Theme.dropFill.setFill()
        shape.fill()
        Theme.accent.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
    }

    /// Secondary text drops under 4.5:1 on the tint, so on a selected row it takes the primary colour.
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

/// Zipboy's own buttons. A view has at most one prominent button, a neon capsule with dark ink; its
/// alternative is the same shape on a quiet fill, so the pair lines up exactly.
final class ActionButton: NSButton {
    let prominent: Bool

    init(_ title: String, symbol: String? = nil, action: Selector?, prominent: Bool) {
        self.prominent = prominent
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Theme.Radius.m
        imagePosition = symbol == nil ? .noImage : .imageLeading
        imageHugsTitle = true
        setButtonType(.momentaryChange)
        self.action = action
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        }
        // An initializer's own assignment skips `didSet`, so it does the same work here.
        label = title
        setAccessibilityLabel(title)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("ActionButton is built in code") }

    /// The plain title; the button draws it in its own colour.
    var label = "" {
        didSet {
            setAccessibilityLabel(label)
            restyle()
        }
    }

    override var isEnabled: Bool {
        didSet { restyle() }
    }

    override var isHighlighted: Bool {
        didSet { restyle() }
    }

    override var wantsUpdateLayer: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width + Theme.Space.xl, height: 30)
    }

    override func updateLayer() {
        restyle()
    }

    /// Whether it wears the neon now. Like the system's default button, it goes quiet while its
    /// window is in the background, so only the window being worked in carries the brand colour.
    var isLit: Bool { prominent && isEnabled && (window?.isMainWindow ?? true) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            center.removeObserver(self, name: name, object: nil)
            if let newWindow {
                center.addObserver(self, selector: #selector(mainChanged), name: name, object: newWindow)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restyle()
    }

    @objc private func mainChanged(_ note: Notification) {
        restyle()
    }

    private func restyle() {
        let fill: NSColor = !isEnabled ? Theme.well : isLit ? Theme.neon : Theme.quiet
        // System fills are translucent, so a press scales their own alpha rather than replacing it.
        let resolved = Theme.cgColor(fill, in: self)
        layer?.backgroundColor = isHighlighted ? resolved.copy(alpha: resolved.alpha * 0.7) : resolved
        let text: NSColor = !isEnabled ? .tertiaryLabelColor : isLit ? Theme.ink : .labelColor
        contentTintColor = text
        attributedTitle = NSAttributedString(
            string: label, attributes: [.font: Theme.Font.button, .foregroundColor: text])
    }
}
