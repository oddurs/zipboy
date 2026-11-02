import AppKit
import ZipboyKit

/// The questions an archive asks: its password, what to do about a name that's taken, and human-readable errors.
@MainActor
enum Prompts {
    enum Resolution {
        case replace, keepBoth, skip
    }

    struct PasswordEntry {
        let password: String
        let rememberInKeychain: Bool
    }

    static func password(for name: String, retry: Bool, in window: NSWindow?) async -> PasswordEntry? {
        let alert = NSAlert()
        alert.messageText = retry ? "Wrong password for “\(name)”" : "“\(name)” is protected with a password"
        alert.informativeText = retry ? "Try again." : "Enter the password to open it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 26, width: 260, height: 24))
        field.placeholderString = "Password"
        let remember = NSButton(
            checkboxWithTitle: "Remember password in Keychain", target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 260, height: 20)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))
        container.addSubview(field)
        container.addSubview(remember)
        alert.accessoryView = container
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        guard response == .alertFirstButtonReturn else { return nil }
        return PasswordEntry(password: field.stringValue, rememberInKeychain: remember.state == .on)
    }

    /// Asks for a new password twice, again until both match. Nil means cancelled.
    static func newPassword(in window: NSWindow) async -> PasswordEntry? {
        var mismatch = false
        while true {
            let alert = NSAlert()
            alert.messageText = mismatch ? "The passwords don’t match" : "Protect this archive with a password"
            alert.informativeText =
                "Everything in it is encrypted with AES-256 when you save. Anyone opening it will need the password."
            let first = NSSecureTextField(frame: NSRect(x: 0, y: 56, width: 260, height: 24))
            first.placeholderString = "Password"
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 26, width: 260, height: 24))
            second.placeholderString = "Verify"
            let remember = NSButton(
                checkboxWithTitle: "Remember password in Keychain", target: nil, action: nil)
            remember.frame = NSRect(x: 0, y: 0, width: 260, height: 20)
            let fields = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 82))
            fields.addSubview(first)
            fields.addSubview(second)
            fields.addSubview(remember)
            first.nextKeyView = second
            alert.accessoryView = fields
            alert.addButton(withTitle: "Set Password")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = first
            guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
            if !first.stringValue.isEmpty, first.stringValue == second.stringValue {
                return PasswordEntry(password: first.stringValue, rememberInKeychain: remember.state == .on)
            }
            mismatch = true
        }
    }

    /// Re-reading names unpacks the archive again from its file. True means go ahead and lose what
    /// hasn't been saved.
    static func discardChanges(toReadNamesAs encoding: TextEncoding, in window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Read names again as \(encoding.title)?"
        alert.informativeText = "The archive is opened again from its file, so changes you haven’t saved are lost."
        alert.addButton(withTitle: "Read Again").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn
    }

    /// Presents an archive or file error with a human-readable explanation and an optional expandable
    /// technical details section so raw `libarchive` or POSIX diagnostics never clutter the main alert.
    static func makeErrorAlert(for error: Error, fileName: String? = nil) -> NSAlert {
        let explanation = ArchiveError.describe(error, fileName: fileName)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = explanation.title
        alert.informativeText = explanation.message
        if let details = explanation.technicalDetails, !details.isEmpty, details != explanation.message {
            let label = NSTextField(wrappingLabelWithString: details)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.isSelectable = true
            label.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
            alert.accessoryView = label
        }
        return alert
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
