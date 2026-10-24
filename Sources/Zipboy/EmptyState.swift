import AppKit

/// What the list shows when it has nothing to list: a tray to drop files into, the archive unzipping
/// while it opens, or that a search found nothing. It sits inside the outline, so drops land on the
/// list; only its button takes clicks.
@MainActor
final class EmptyStateView: NSView {
    enum Mode: Equatable {
        case drop, noResults
        case loading(Double)
    }

    var mode = Mode.drop {
        didSet { if mode != oldValue { update() } }
    }

    /// Something is being dragged over the empty list.
    var highlighted = false {
        didSet { if highlighted != oldValue { updateHighlight() } }
    }

    private let tray = NSView()
    private let border = CAShapeLayer()
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let choose = NSButton(
        title: "Choose Files…", target: nil, action: #selector(BrowserViewController.addFiles(_:)))
    private let zipper = ZipperProgressView()
    private let stack: NSStackView

    override init(frame: NSRect) {
        stack = NSStackView(views: [glyph, zipper, title, detail, choose])
        super.init(frame: frame)

        tray.wantsLayer = true
        tray.layer?.addSublayer(border)
        border.fillColor = nil
        border.lineWidth = 2
        border.lineDashPattern = [10, 7]
        border.lineCap = .round
        tray.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tray)

        glyph.symbolConfiguration = .init(pointSize: 40, weight: .light)
        title.font = Theme.rounded(18, .semibold)
        title.alignment = .center
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        choose.isBordered = false
        choose.font = Theme.rounded(13, .semibold)
        choose.setAccessibilityLabel("Choose files to add")

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: glyph)
        stack.setCustomSpacing(18, after: zipper)
        stack.setCustomSpacing(12, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            tray.centerXAnchor.constraint(equalTo: centerXAnchor),
            tray.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            tray.widthAnchor.constraint(equalToConstant: 340),
            tray.heightAnchor.constraint(equalToConstant: 230),
            stack.centerXAnchor.constraint(equalTo: tray.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: tray.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: tray.widthAnchor, constant: -40),
            zipper.widthAnchor.constraint(equalToConstant: 240),
            zipper.heightAnchor.constraint(equalToConstant: 34),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        update()
    }

    required init?(coder: NSCoder) { fatalError("EmptyStateView is built in code") }

    /// Drops go through to the list underneath; only the Choose Files… button is clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === choose || hit?.isDescendant(of: choose) == true ? hit : nil
    }

    override func layout() {
        super.layout()
        border.frame = tray.bounds
        border.path = CGPath(
            roundedRect: tray.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 26, cornerHeight: 26, transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    /// Whether the tray's dashes are marching, for tests.
    var isAnimating: Bool { border.animation(forKey: "march") != nil }

    /// The Choose Files… button, for tests.
    var chooseButton: NSButton { choose }

    private func update() {
        let loading: Double? = if case .loading(let done) = mode { done } else { nil }
        tray.isHidden = mode != .drop
        glyph.isHidden = loading != nil
        zipper.isHidden = loading == nil
        choose.isHidden = mode != .drop
        switch mode {
        case .drop:
            glyph.image = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil)
            title.stringValue = "Drop files here"
            detail.stringValue = "Files and folders are zipped up as you go."
        case .noResults:
            glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            title.stringValue = "No matches"
            detail.stringValue = "Nothing in this archive has that in its name."
        case .loading(let done):
            zipper.progress = done
            title.stringValue = "Unzipping…"
            detail.stringValue = "\(Int(done * 100))%"
        }
        setAccessibilityLabel([title.stringValue, detail.stringValue].joined(separator: ". "))
        updateHighlight()
    }

    private func updateHighlight() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let lit = highlighted && mode == .drop
            border.strokeColor = (lit ? Theme.accent : NSColor.tertiaryLabelColor).cgColor
            border.fillColor = lit ? Theme.dropFill.cgColor : nil
        }
        glyph.contentTintColor = mode == .drop ? Theme.accent : .tertiaryLabelColor
        title.textColor = mode == .drop ? .labelColor : .secondaryLabelColor
        choose.contentTintColor = Theme.accent

        let lit = highlighted && mode == .drop
        border.removeAllAnimations()
        guard lit, !Theme.reduceMotion() else { return }
        // The dashes march round the tray, and the glyph hops, while a drop is waiting.
        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = -34
        march.duration = 0.6
        march.repeatCount = .infinity
        border.add(march, forKey: "march")
        glyph.addSymbolEffect(.bounce)
    }
}

/// Opening an archive, drawn as a zipper coming undone: the slider travels with the progress, the
/// teeth behind it part, and the teeth ahead stay locked.
@MainActor
final class ZipperProgressView: NSView {
    var progress: Double = 0 {
        didSet {
            needsDisplay = true
            setAccessibilityValue("\(Int(progress * 100)) percent")
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Unzipping")
    }

    required init?(coder: NSCoder) { fatalError("ZipperProgressView is built in code") }

    override func draw(_ dirtyRect: NSRect) {
        let teeth = 22
        let pitch = (bounds.width - 24) / CGFloat(teeth)
        let midY = bounds.midY
        let slider = 12 + CGFloat(min(max(progress, 0), 1)) * (bounds.width - 24)
        let tooth = NSSize(width: pitch * 0.62, height: 6)

        for index in 0..<teeth {
            let x = 12 + CGFloat(index) * pitch
            // Behind the slider the two sides spread apart, wider the further back they are.
            let behind = x + pitch / 2 < slider
            let spread: CGFloat = behind ? min(15, 2 + (slider - x) * 0.12) : 0
            let color = behind ? NSColor.tertiaryLabelColor : Theme.accent
            color.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: x, y: midY + 1 + spread, width: tooth.width, height: tooth.height),
                xRadius: 2, yRadius: 2
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: x + pitch / 2, y: midY - 1 - tooth.height - spread, width: tooth.width, height: tooth.height),
                xRadius: 2, yRadius: 2
            ).fill()
        }

        // The slider, with its pull tab hanging below.
        Theme.accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: slider - 9, y: midY - 7, width: 18, height: 14), xRadius: 5, yRadius: 5
        ).fill()
        NSBezierPath(
            roundedRect: NSRect(x: slider - 3.5, y: midY - 7 - 11, width: 7, height: 13), xRadius: 3.5, yRadius: 3.5
        ).fill()
    }
}
