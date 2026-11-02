import AppKit

/// What the list shows when it has nothing to list, laid out as the system's content-unavailable views
/// are: a symbol, a heading, a line of help, and at most one button. It sits inside the outline, so
/// drops land on the list; only its button takes clicks.
@MainActor
final class EmptyStateView: NSView {
    enum Mode: Equatable {
        case drop
        case noResults(String)
        case loading(Double)
    }

    var mode = Mode.drop {
        didSet { if mode != oldValue { update() } }
    }

    /// Something that would be accepted is being dragged over the empty list.
    var highlighted = false {
        didSet { if highlighted != oldValue { updateHighlight(bouncing: highlighted) } }
    }

    /// The drop area: a dashed outline at rest, the accent colour while a drop is waiting.
    private let area = CAShapeLayer()
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    /// The window's one prominent action while there is nothing else to act on: the inspector hides
    /// its footer for an empty archive.
    private let choose = NSButton.push(
        "Choose Files…", action: #selector(BrowserViewController.addFiles(_:)), prominent: true)
    private let stack: NSStackView

    override init(frame: NSRect) {
        stack = NSStackView(views: [glyph, title, detail, progress, choose])
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(area)
        area.lineWidth = 1.5
        area.lineCap = .round

        glyph.symbolConfiguration = .init(pointSize: 44, weight: .light)
        title.font = Theme.Font.heading
        title.alignment = .center
        title.textColor = .secondaryLabelColor
        detail.font = Theme.Font.body
        detail.textColor = .tertiaryLabelColor
        detail.alignment = .center
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        choose.setAccessibilityLabel("Choose files to add")

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Theme.Space.xs
        stack.setCustomSpacing(Theme.Space.l, after: glyph)
        stack.setCustomSpacing(Theme.Space.s, after: title)
        stack.setCustomSpacing(Theme.Space.l, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Theme.Space.l),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * Theme.Space.xl),
            progress.widthAnchor.constraint(equalToConstant: 200),
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
        // The whole list is the drop area, inset so its edge sits clear of the window's.
        let rect = bounds.insetBy(dx: Theme.Space.m, dy: Theme.Space.m)
        area.frame = bounds
        area.path = CGPath(
            roundedRect: rect, cornerWidth: Theme.Radius.l, cornerHeight: Theme.Radius.l, transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight(bouncing: false)
    }

    /// The Choose Files… button, for tests.
    var chooseButton: NSButton { choose }

    /// The drop area's outline colour, for tests.
    var outlineColor: CGColor? { area.strokeColor }

    private func update() {
        let loading: Double? = if case .loading(let done) = mode { done } else { nil }
        glyph.isHidden = loading != nil
        progress.isHidden = loading == nil
        choose.isHidden = mode != .drop
        area.isHidden = mode != .drop
        switch mode {
        case .drop:
            glyph.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
            title.stringValue = "Drop Files Here"
            detail.stringValue = "Everything you add is zipped as you go."
        case .noResults(let query):
            glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            title.stringValue = "No Results for “\(query)”"
            detail.stringValue = "Check the spelling or try a new search."
        case .loading(let done):
            progress.doubleValue = done
            title.stringValue = "Unzipping…"
            detail.stringValue = ""
            progress.setAccessibilityValue("\(Int(done * 100)) percent")
        }
        detail.isHidden = detail.stringValue.isEmpty
        setAccessibilityLabel([title.stringValue, detail.stringValue].filter { !$0.isEmpty }.joined(separator: ". "))
        updateHighlight(bouncing: false)
    }

    private func updateHighlight(bouncing: Bool) {
        let lit = highlighted && mode == .drop
        effectiveAppearance.performAsCurrentDrawingAppearance {
            area.strokeColor = (lit ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            area.fillColor = lit ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor : nil
        }
        // Dashes at rest say "a place to put things"; a solid edge says "let go".
        area.lineDashPattern = lit ? nil : [6, 5]
        area.lineWidth = lit ? 2.5 : 1.5
        glyph.contentTintColor = lit ? .controlAccentColor : .tertiaryLabelColor
        if bouncing, lit, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            glyph.addSymbolEffect(.bounce)
        }
    }
}
