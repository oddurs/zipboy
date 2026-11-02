import AppKit

/// A quick welcome on first launch: three pages, each with Mugi in the pose meant for it. Skippable from
/// any page, and back from Help > Welcome to Zipboy.
@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    struct Page {
        let pose: Mugi.Pose
        let title: String
        let body: String
    }

    static let pages = [
        Page(
            pose: .welcome, title: "Welcome to Zipboy",
            body: "Open any archive to see what’s inside, without unpacking a thing. ZIP, RAR, 7z, and more."),
        Page(
            pose: .presenting, title: "Drag in, drag out",
            body:
                "Drop files on a window to add them, and drag items to Finder to extract them. Your archive saves as you go."
        ),
        Page(
            pose: .celebrate, title: "You’re all set",
            body:
                "Press Space to preview anything, here or in Finder. This tour is in the Help menu if you want it again."
        ),
    ]

    private(set) var index = 0
    let mugi = MugiView(.welcome)
    let heading = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let dots = PageDots(count: pages.count)
    let back = NSButton(title: "Back", target: nil, action: nil)
    let skip = NSButton(title: "Skip", target: nil, action: nil)
    let next = NSButton.push("Continue", action: nil, prominent: true)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Zipboy"
        super.init(window: window)

        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.alignment = .center
        message.font = Theme.Font.body
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        for button in [back, skip] {
            button.bezelStyle = .push
            button.controlSize = .large
            button.target = self
        }
        back.action = #selector(goBack(_:))
        skip.action = #selector(finish(_:))
        next.target = self
        next.action = #selector(goNext(_:))
        // Here Return means "on", and Escape means "enough", as in any Mac assistant.
        next.keyEquivalent = "\r"
        skip.keyEquivalent = "\u{1b}"

        let text = NSStackView(views: [heading, message])
        text.orientation = .vertical
        text.spacing = Theme.Space.s
        let buttons = NSStackView(views: [skip, back, NSView(), next])
        buttons.orientation = .horizontal
        buttons.spacing = Theme.Space.s
        let stack = NSStackView(views: [mugi, text, dots, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Theme.Space.l
        stack.setCustomSpacing(Theme.Space.xl, after: dots)
        stack.edgeInsets = NSEdgeInsets(
            top: Theme.Space.xl + 12, left: Theme.Space.xl, bottom: Theme.Space.xl, right: Theme.Space.xl)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 480),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            mugi.widthAnchor.constraint(equalToConstant: 200),
            mugi.heightAnchor.constraint(equalToConstant: 200),
            message.widthAnchor.constraint(equalToConstant: 360),
            // Fixed for the longest page, so the buttons don't jump as the pages turn.
            message.heightAnchor.constraint(equalToConstant: 54),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Theme.Space.xl),
        ])
        window.contentView = content
        // As tall as the pages need and no taller, so nothing floats in a gap.
        window.setContentSize(content.fittingSize)
        window.center()
        show(page: 0)
    }

    required init?(coder: NSCoder) { fatalError("WelcomeWindowController is built in code") }

    func present() {
        show(page: 0)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func show(page: Int) {
        index = min(max(page, 0), Self.pages.count - 1)
        let page = Self.pages[index]
        mugi.pose = page.pose
        heading.stringValue = page.title
        message.stringValue = page.body
        dots.current = index
        let last = index == Self.pages.count - 1
        next.title = last ? "Get Started" : "Continue"
        back.isHidden = index == 0
        skip.isHidden = last
    }

    @objc func goNext(_ sender: Any?) {
        index == Self.pages.count - 1 ? finish(sender) : show(page: index + 1)
    }

    @objc func goBack(_ sender: Any?) {
        show(page: index - 1)
    }

    @objc func finish(_ sender: Any?) {
        window?.orderOut(sender)
    }

    /// The arrow keys turn the pages too.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124: goNext(nil)
        case 123: goBack(nil)
        default: super.keyDown(with: event)
        }
    }
}

/// Small dots for the pages, the current one filled with the accent.
@MainActor
final class PageDots: NSView {
    let count: Int
    var current = 0 {
        didSet {
            needsDisplay = true
            setAccessibilityValue("Page \(current + 1) of \(count)")
        }
    }

    init(count: Int) {
        self.count = count
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue("Page 1 of \(count)")
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: CGFloat(count) * 14),
            heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("PageDots is built in code") }

    override func draw(_ dirtyRect: NSRect) {
        for dot in 0..<count {
            (dot == current ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: CGFloat(dot) * 14 + 3, y: 0, width: 8, height: 8)).fill()
        }
    }
}
