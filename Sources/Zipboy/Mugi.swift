import AppKit

/// Mugi, Zipboy's mascot: a cream mochi bear with an apricot zippered pouch. Each pose has the use the
/// Mugi system gives it, and Mugi appears only in quiet moments (About, the welcome), never in the
/// working window.
@MainActor
enum Mugi {
    enum Pose: String, CaseIterable {
        /// "The original": identity, About.
        case neutral
        /// "Hello there": welcome screens and introductions.
        case welcome
        /// "This way": showing how something works.
        case presenting
        /// "Nicely done": finishing.
        case celebrate

        /// What VoiceOver says, from the Mugi system's suggested alt text.
        var description: String {
            switch self {
            case .neutral: "Mugi, a cream bear with an orange zippered pouch, standing."
            case .welcome: "Mugi, a cream bear with an orange zippered pouch, waving hello."
            case .presenting: "Mugi, a cream bear with an orange zippered pouch, presenting with an open paw."
            case .celebrate: "Mugi, a cream bear with an orange zippered pouch, celebrating."
            }
        }
    }

    /// Where the art is: the app's Resources. Tests point it at the source tree, which has the same files.
    static var resources: URL? = Bundle.main.resourceURL

    static func image(_ pose: Pose) -> NSImage? {
        resources.flatMap { NSImage(contentsOf: $0.appendingPathComponent("Mugi/\(pose.rawValue).png")) }
    }

    /// The app icon for an appearance. The light one is the bundle's own; Finder can only show that one,
    /// since a dark Finder icon needs Xcode's asset compiler.
    static func appIcon(for appearance: NSAppearance) -> NSImage? {
        guard Theme.isDark(appearance) else { return nil }
        return resources.flatMap { NSImage(contentsOf: $0.appendingPathComponent("AppIconDark.icns")) }
    }
}

/// Mugi in a pose, standing on a soft contact shadow so the figure is grounded rather than floating,
/// in either appearance. The shadow deepens in Dark Mode, where a light one would vanish.
@MainActor
final class MugiView: NSView {
    var pose: Mugi.Pose {
        didSet { update() }
    }

    private let picture = NSImageView()

    init(_ pose: Mugi.Pose) {
        self.pose = pose
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picture)
        NSLayoutConstraint.activate([
            picture.topAnchor.constraint(equalTo: topAnchor),
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            picture.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        update()
    }

    required init?(coder: NSCoder) { fatalError("MugiView is built in code") }

    private func update() {
        picture.image = Mugi.image(pose)
        setAccessibilityLabel(pose.description)
        needsDisplay = true
    }

    /// The shadow sits under the soles: the poses' feet end about 9% above the foot of the square art.
    override func draw(_ dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        let foot = NSRect(
            x: bounds.midX - bounds.width * 0.3, y: bounds.minY + bounds.height * 0.005,
            width: bounds.width * 0.6, height: bounds.height * 0.07)
        let gradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(dark ? 0.55 : 0.2), NSColor.black.withAlphaComponent(0),
        ])
        gradient?.draw(in: NSBezierPath(ovalIn: foot), relativeCenterPosition: .zero)
    }

    override var isFlipped: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
