import AppKit
import ZipboyKit

/// Offline Help guide window (`Help > Zipboy Help`, `⌘?`), searchable across all archive workflows.
@MainActor
final class HelpWindowController: NSWindowController, NSSearchFieldDelegate {
    static let shared = HelpWindowController()

    typealias Section = HelpTopics.Topic

    static let allSections = HelpTopics.all

    let searchField = NSSearchField()
    private let stack = NSStackView()
    private(set) var visibleSections: [Section] = allSections

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zipboy Help"
        window.minSize = NSSize(width: 440, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func filter(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            visibleSections = Self.allSections
        } else {
            visibleSections = Self.allSections.filter { section in
                section.title.lowercased().contains(trimmed)
                    || section.summary.lowercased().contains(trimmed)
                    || section.keywords.contains(where: { $0.contains(trimmed) })
            }
        }
        rebuildCards()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter(searchField.stringValue)
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))

        searchField.placeholderString = "Search Help (e.g. password, verify, export)"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedHelpView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scroll.documentView = documentView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        rebuildCards()
        window.contentView = root
    }

    private func rebuildCards() {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for section in visibleSections {
            let box = NSBox()
            box.boxType = .custom
            box.cornerRadius = Theme.Radius.m
            box.borderWidth = 1
            box.borderColor = .separatorColor
            box.fillColor = Theme.well
            box.contentViewMargins = NSSize(width: Theme.Space.l, height: Theme.Space.m)
            box.translatesAutoresizingMaskIntoConstraints = false

            let inner = NSStackView()
            inner.orientation = .vertical
            inner.alignment = .leading
            inner.spacing = 4

            let heading = NSTextField(labelWithString: section.title)
            heading.font = Theme.Font.title
            heading.textColor = .labelColor

            let body = NSTextField(wrappingLabelWithString: section.summary)
            body.font = Theme.Font.callout
            body.textColor = .secondaryLabelColor

            inner.addArrangedSubview(heading)
            inner.addArrangedSubview(body)
            box.contentView = inner
            stack.addArrangedSubview(box)
            box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
    }
}

private final class FlippedHelpView: NSView {
    override var isFlipped: Bool { true }
}
