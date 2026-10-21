import AppKit

/// The questions an archive asks: its password, and what to do about a name that's taken.
@MainActor
enum Prompts {
    enum Resolution {
        case replace, keepBoth, skip
    }

    static func password(for name: String, retry: Bool, in window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = retry ? "Wrong password for “\(name)”" : "“\(name)” is protected with a password"
        alert.informativeText = retry ? "Try again." : "Enter the password to open it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Asks for a new password twice, again until both match. Nil means cancelled.
    static func newPassword(in window: NSWindow) async -> String? {
        var mismatch = false
        while true {
            let alert = NSAlert()
            alert.messageText = mismatch ? "The passwords don’t match" : "Protect this archive with a password"
            alert.informativeText =
                "Everything in it is encrypted with AES-256 when you save. Anyone opening it will need the password."
            let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
            first.placeholderString = "Password"
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            second.placeholderString = "Verify"
            let fields = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
            fields.addSubview(first)
            fields.addSubview(second)
            first.nextKeyView = second
            alert.accessoryView = fields
            alert.addButton(withTitle: "Set Password")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = first
            guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
            if !first.stringValue.isEmpty, first.stringValue == second.stringValue { return first.stringValue }
            mismatch = true
        }
    }

    /// Finder's question for a name collision, with "Apply to All" when more are coming. Nil means stop.
    @MainActor
    final class Conflicts {
        private let window: NSWindow?
        private var remembered: Resolution?
        private var remaining: Int

        init(window: NSWindow?, count: Int) {
            self.window = window
            self.remaining = count
        }

        func resolve(_ name: String) async -> Resolution? {
            remaining -= 1
            if let remembered { return remembered }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "An item named “\(name)” already exists in this location."
            alert.informativeText = "Do you want to replace it with the one you’re adding?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Keep Both")
            alert.addButton(withTitle: "Skip")
            alert.addButton(withTitle: "Stop")
            alert.showsSuppressionButton = remaining > 0
            alert.suppressionButton?.title = "Apply to All"
            let response: NSApplication.ModalResponse
            if let window {
                response = await alert.beginSheetModal(for: window)
            } else {
                response = alert.runModal()
            }
            let resolution: Resolution? =
                switch response {
                case .alertFirstButtonReturn: .replace
                case .alertSecondButtonReturn: .keepBoth
                case .alertThirdButtonReturn: .skip
                default: nil
                }
            if alert.suppressionButton?.state == .on { remembered = resolution }
            return resolution
        }
    }
}
