import Foundation
import Testing

@testable import Zipboy

@Suite struct WorkspaceTests {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyWorkspaces-\(UUID().uuidString)")

    /// The pid of a process that has already exited.
    func deadPID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @Test func sweepKeepsWorkspacesOfRunningProcesses() throws {
        let mine = try Workspace(in: base)
        let abandoned = try Workspace(in: base, owner: try deadPID())
        let unowned = base.appendingPathComponent("from-an-older-build")
        try FileManager.default.createDirectory(at: unowned, withIntermediateDirectories: true)
        // Pid 0 means "my process group" to kill(2), which would always look alive.
        let damaged = try Workspace(in: base, owner: 0)

        Workspace.removeAbandoned(in: base)

        // A second Zipboy launching must not take the first one's open archives away.
        #expect(FileManager.default.fileExists(atPath: mine.contents.path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.folder.path))
        #expect(!FileManager.default.fileExists(atPath: unowned.path))
        #expect(!FileManager.default.fileExists(atPath: damaged.folder.path))
    }
}
