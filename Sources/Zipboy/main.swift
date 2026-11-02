import AppKit

MainActor.assumeIsolated {
    // Before AppKit reads the accent, so the first window already draws in green.
    Theme.registerAccent()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.mainMenu = MainMenu.make()
    withExtendedLifetime(delegate) { app.run() }
}
