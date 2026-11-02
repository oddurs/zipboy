import AppKit

/// Zipboy's look is the system's: its accent, selection, controls, and type. What lives here is the
/// spacing, shape, and type scale the views share, so the window's own layout stays one layout.
@MainActor
enum Theme {
    // MARK: Colour

    /// Recessed surfaces such as the preview well: a step off the window, in either appearance.
    static let well = NSColor(name: "ZipboyWell") { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.045) : NSColor(white: 0, alpha: 0.035)
    }

    /// Small pills: a translucent step off whatever they sit on. Explicit values, because the system
    /// fills resolve to opaque black when a layer asks for them.
    static let quiet = NSColor(name: "ZipboyQuiet") { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.06)
    }

    nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
        /// Small controls.
        static let s: CGFloat = 6
        /// Cards.
        static let m: CGFloat = 10
        /// Wells and drop areas.
        static let l: CGFloat = 14
    }

    /// The type ramp, all SF Pro at the sizes macOS uses for the same jobs.
    enum Font {
        static var title: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var heading: NSFont { .systemFont(ofSize: 17, weight: .semibold) }
        static var body: NSFont { .systemFont(ofSize: 13) }
        static var callout: NSFont { .systemFont(ofSize: 12) }
        static var label: NSFont { .systemFont(ofSize: 11, weight: .medium) }
        static var digits: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }
        static var code: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    }

    /// Resolves a dynamic colour for a layer, which can't follow appearance changes on its own.
    static func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

extension NSButton {
    /// A large push button. A view's one prominent action takes the accent, as a default button does,
    /// but no Return key: in the list, Return renames.
    static func push(_ title: String, action: Selector?, prominent: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: nil, action: action)
        button.bezelStyle = .push
        button.controlSize = .large
        if prominent { button.bezelColor = .controlAccentColor }
        return button
    }

    /// Whether this is its view's prominent action.
    var isProminent: Bool { bezelColor == .controlAccentColor }
}
