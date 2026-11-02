import AppKit
import ZipboyKit

/// AppleScript's `extract` and `compress`, which Shortcuts reaches through Run AppleScript. Each does
/// what the Finder service of the same name does, off the main thread, holding the script's reply
/// until it's done so a big archive doesn't freeze the app.
enum Scripting {
    /// An AppleScript error for a path that isn't there, naming it.
    struct Missing: Error {
        let path: String
    }

    nonisolated static func extract(_ archive: URL, to folder: URL?) throws -> [URL] {
        try require([archive] + [folder].compactMap { $0 })
        return try AppDelegate.extractArchives([archive], into: folder)
    }

    nonisolated static func compress(_ files: [URL], into folder: URL?) throws -> URL {
        try require(files + [folder].compactMap { $0 })
        return try AppDelegate.compressFiles(files, into: folder)
    }

    private nonisolated static func require(_ urls: [URL]) throws {
        if let gone = urls.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw Missing(path: gone.path)
        }
    }

    /// The number and message a script sees: -43 for a missing file, as the Finder reports it.
    nonisolated static func scriptError(for error: Error) -> (number: Int, message: String) {
        if let missing = error as? Missing { return (-43, "Can’t find “\(missing.path)”.") }
        let explanation = ArchiveError.describe(error)
        return (-2700, [explanation.title, explanation.message].filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// The paths a script passed: a single file, or a list of them.
    nonisolated static func urls(from value: Any?) -> [URL] {
        if let url = value as? URL { return [url] }
        return (value as? [Any])?.compactMap { $0 as? URL } ?? []
    }
}

/// Runs a script command's work in the background and hands the result back when it's ready.
private func runSuspended(_ command: NSScriptCommand, _ work: @escaping @Sendable () throws -> Any) -> Any? {
    command.suspendExecution()
    let reply = UncheckedBox(command)
    DispatchQueue.global(qos: .userInitiated).async {
        let outcome = Result { try work() }
        DispatchQueue.main.async {
            let command = reply.value
            switch outcome {
            case .success(let value):
                command.resumeExecution(withResult: value)
            case .failure(let error):
                let (number, message) = Scripting.scriptError(for: error)
                command.scriptErrorNumber = number
                command.scriptErrorString = message
                command.resumeExecution(withResult: nil)
            }
        }
    }
    return nil
}

/// NSScriptCommand isn't Sendable, but it's only touched again on the main thread it came from.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

@objc(ZipboyExtractCommand)
final class ExtractCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let archive = Scripting.urls(from: directParameter).first else {
            scriptErrorNumber = -1708
            scriptErrorString = "Say which archive to extract."
            return nil
        }
        let folder = evaluatedArguments?["Destination"] as? URL
        return runSuspended(self) { try Scripting.extract(archive, to: folder) as [URL] as NSArray }
    }
}

@objc(ZipboyCompressCommand)
final class CompressCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let files = Scripting.urls(from: directParameter)
        guard !files.isEmpty else {
            scriptErrorNumber = -1708
            scriptErrorString = "Say which files to compress."
            return nil
        }
        let folder = evaluatedArguments?["Destination"] as? URL
        return runSuspended(self) { try Scripting.compress(files, into: folder) as NSURL }
    }
}
