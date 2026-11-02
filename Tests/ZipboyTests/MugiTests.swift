import AppKit
import Testing
import ZipboyKit

@testable import Zipboy

/// Mugi's icon, About, and welcome, drawn in both appearances.
@MainActor
@Suite(.serialized) struct MugiTests {
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources")

    init() { Mugi.resources = Self.resources }

    /// Draws `view` over the window background of `look`, as it appears on screen, and keeps a copy in
    /// the temporary folder for a person to look at.
    func render(_ view: NSView, _ look: NSAppearance.Name, named name: String) throws -> NSBitmapImageRep {
        let appearance = try #require(NSAppearance(named: look))
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()
        let layer = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: layer)
        let size = view.bounds.size
        let out = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: layer.pixelsWide, pixelsHigh: layer.pixelsHigh, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0))
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        layer.draw(
            in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyRenders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try out.representation(using: .png, properties: [:])?.write(
            to: folder.appendingPathComponent("\(name)-\(look == .darkAqua ? "dark" : "light").png"))
        return out
    }

    func brightness(_ rep: NSBitmapImageRep, atX x: Double, y: Double) -> Double {
        let color = rep.colorAt(x: Int(Double(rep.pixelsWide) * x), y: Int(Double(rep.pixelsHigh) * y))
        return (color?.usingColorSpace(.deviceRGB)?.brightnessComponent).map(Double.init) ?? -1
    }

    @Test func everyPoseHasArtAndAName() {
        for pose in Mugi.Pose.allCases {
            #expect(Mugi.image(pose) != nil, "\(pose)")
            #expect(MugiView(pose).accessibilityLabel()?.hasPrefix("Mugi") == true)
        }
    }

    @Test func theIconFollowsTheAppearance() throws {
        #expect(Mugi.appIcon(for: try #require(NSAppearance(named: .aqua))) == nil)
        #expect(Mugi.appIcon(for: try #require(NSAppearance(named: .darkAqua))) != nil)
    }

    /// How light the icon's backdrop is, left of Mugi, where the light and dark renders differ most.
    func backdrop(_ icon: NSImage?) throws -> Double {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        try #require(icon).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        NSGraphicsContext.restoreGraphicsState()
        return brightness(rep, atX: 0.2, y: 0.5)
    }

    @Test func theRunningAppSwitchesItsIconWithTheAppearance() throws {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        defer { app.appearance = nil }
        app.appearance = NSAppearance(named: .aqua)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        app.appearance = NSAppearance(named: .darkAqua)
        #expect(try backdrop(app.applicationIconImage) < 0.4)
        app.appearance = NSAppearance(named: .aqua)
        // Back to the bundle's own icon, which in a test runner is the generic one: what matters is
        // that the dark Mugi has gone.
        #expect(
            try backdrop(app.applicationIconImage)
                != backdrop(Mugi.appIcon(for: try #require(NSAppearance(named: .darkAqua)))))
        withExtendedLifetime(delegate) {}
    }

    @Test func mugiStandsOnAShadowInBothAppearances() throws {
        let view = MugiView(.neutral)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        // The shadow's centre, just under the feet, against the plain window beside it.
        for look in [NSAppearance.Name.aqua, .darkAqua] {
            let rep = try render(view, look, named: "mugi")
            let shadow = brightness(rep, atX: 0.5, y: 1 - 0.035)
            let ground = brightness(rep, atX: 0.05, y: 1 - 0.035)
            #expect(shadow < ground - 0.02, "\(look.rawValue): shadow \(shadow), ground \(ground)")
            // Mugi's cream body, in the middle, stays light in either appearance.
            #expect(brightness(rep, atX: 0.5, y: 0.45) > 0.8, "\(look.rawValue)")
        }
    }

    @Test func aboutShowsMugiTheVersionAndTheCredits() throws {
        let about = AboutWindowController()
        let content = try #require(about.window?.contentView)
        #expect(about.version.stringValue.hasPrefix("Version "))
        #expect(about.credits.string.contains("libarchive"))
        content.frame = NSRect(origin: .zero, size: content.fittingSize)
        for look in [NSAppearance.Name.aqua, .darkAqua] { _ = try render(content, look, named: "about") }
    }

    @Test func theWelcomeTurnsItsPagesAndCanBeSkipped() throws {
        let welcome = WelcomeWindowController()
        #expect(WelcomeWindowController.pages.map(\.pose) == [.welcome, .presenting, .celebrate])
        #expect(welcome.back.isHidden && !welcome.skip.isHidden)
        #expect(welcome.next.title == "Continue")
        let content = try #require(welcome.window?.contentView)
        content.frame = NSRect(origin: .zero, size: content.fittingSize)
        for page in 0..<3 {
            welcome.show(page: page)
            for look in [NSAppearance.Name.aqua, .darkAqua] {
                _ = try render(content, look, named: "welcome-\(page + 1)")
            }
        }
        welcome.show(page: 0)
        welcome.goNext(nil)
        #expect(welcome.index == 1 && welcome.mugi.pose == .presenting && !welcome.back.isHidden)
        welcome.goNext(nil)
        #expect(welcome.next.title == "Get Started" && welcome.skip.isHidden)
        #expect(welcome.dots.accessibilityValue() as? String == "Page 3 of 3")
        welcome.goBack(nil)
        #expect(welcome.index == 1)
        // Escape skips and Return goes on, from any page.
        #expect(welcome.skip.keyEquivalent == "\u{1b}" && welcome.next.keyEquivalent == "\r")
    }

    @Test func theWelcomeShowsOnceAndComesBackFromHelp() {
        let suite = "com.oddurs.zipboy.mugitests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        #expect(settings.shouldShowWelcomeOnce())
        #expect(!settings.shouldShowWelcomeOnce())

        _ = NSApplication.shared
        let help = MainMenu.make().item(withTitle: "Help")?.submenu
        #expect(help?.item(withTitle: "Welcome to Zipboy")?.action == #selector(AppDelegate.showWelcome(_:)))
    }
}
