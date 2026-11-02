import AppKit

/// About Zipboy: Mugi, the name and version, a line on what it is, and the credits with their links.
@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    let version = NSTextField(labelWithString: "")
    let credits = NSTextView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "About Zipboy"
        super.init(window: window)

        let mugi = MugiView(.neutral)
        let name = NSTextField(labelWithString: "Zipboy")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        version.stringValue = "Version \(short) (\(build))"
        version.font = Theme.Font.callout
        version.textColor = .secondaryLabelColor
        version.isSelectable = true
        let tagline = NSTextField(
            wrappingLabelWithString: "Opens every archive, and zips everything you add as you go.")
        tagline.font = Theme.Font.body
        tagline.alignment = .center

        // A text view, not a label, so the links in the credits can be clicked.
        credits.textStorage?.setAttributedString(AppDelegate.credits)
        credits.isEditable = false
        credits.isSelectable = true
        credits.drawsBackground = false
        credits.textContainerInset = .zero
        credits.isVerticallyResizable = false
        credits.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [mugi, name, version, tagline, credits])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Theme.Space.xs
        stack.setCustomSpacing(Theme.Space.m, after: mugi)
        stack.setCustomSpacing(Theme.Space.l, after: version)
        stack.setCustomSpacing(Theme.Space.l, after: tagline)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 360),
            mugi.widthAnchor.constraint(equalToConstant: 168),
            mugi.heightAnchor.constraint(equalToConstant: 168),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Theme.Space.xl + 12),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Theme.Space.xl),
            tagline.widthAnchor.constraint(equalToConstant: 280),
            credits.widthAnchor.constraint(equalToConstant: 300),
            credits.heightAnchor.constraint(equalToConstant: 52),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("AboutWindowController is built in code") }
}
