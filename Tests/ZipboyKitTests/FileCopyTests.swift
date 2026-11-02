import Foundation
import Testing

@testable import ZipboyKit

struct FileCopyTests {
    func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("src/inner"), withIntermediateDirectories: true)
        try Data(count: 3 << 20).write(to: dir.appendingPathComponent("src/big.bin"))
        try Data("small".utf8).write(to: dir.appendingPathComponent("src/inner/small.txt"))
        return dir
    }

    @Test func copiesAFolderAndCountsEveryByte() throws {
        let dir = try folder()
        let source = dir.appendingPathComponent("src")
        let total = FileCopy.size(of: [source])
        #expect(total == (3 << 20) + 5)
        var last: Int64 = 0
        try FileCopy.copy(source, to: dir.appendingPathComponent("dst"), clone: false) {
            last = $0
            return true
        }
        #expect(last == total)
        #expect(try Data(contentsOf: dir.appendingPathComponent("dst/inner/small.txt")) == Data("small".utf8))
    }

    @Test func stoppingRemovesWhatWasWritten() throws {
        let dir = try folder()
        let destination = dir.appendingPathComponent("dst")
        #expect(throws: ArchiveError.cancelled) {
            try FileCopy.copy(dir.appendingPathComponent("src"), to: destination, clone: false) { _ in false }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func refusesToOverwrite() throws {
        let dir = try folder()
        let destination = dir.appendingPathComponent("taken.bin")
        try Data("keep".utf8).write(to: destination)
        #expect(throws: (any Error).self) {
            try FileCopy.copy(dir.appendingPathComponent("src/big.bin"), to: destination) { _ in true }
        }
        #expect(try Data(contentsOf: destination) == Data("keep".utf8))
    }

    @Test func cloningStillCopies() throws {
        let dir = try folder()
        try FileCopy.copy(dir.appendingPathComponent("src"), to: dir.appendingPathComponent("dst")) { _ in true }
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("dst/big.bin").path))
    }
}

struct FileCopyPermissionTests {
    @Test func copiesIntoAReadOnlyFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ro-\(UUID().uuidString)")
        let locked = dir.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: locked.appendingPathComponent("inside.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("Copy").path)
        }
        try FileCopy.copy(locked, to: dir.appendingPathComponent("Copy"), clone: false) { _ in true }
        #expect(try Data(contentsOf: dir.appendingPathComponent("Copy/inside.txt")) == Data("x".utf8))
    }

    @Test func aFileThatCantBeReadFailsTheCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        let secret = dir.appendingPathComponent("src/secret.txt")
        try Data("x".utf8).write(to: secret)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path) }
        // Skipping it silently and reporting success would lose the file without a word.
        #expect(throws: (any Error).self) {
            try FileCopy.copy(dir.appendingPathComponent("src"), to: dir.appendingPathComponent("dst"), clone: false) {
                _ in true
            }
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("dst").path))
    }
}
