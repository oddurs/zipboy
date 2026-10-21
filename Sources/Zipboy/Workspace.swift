import Foundation

/// The temporary folder an open archive is unpacked into. `contents` holds the archive as it will be
/// saved; `holding` keeps removed and incoming items on the same volume, so every edit is a rename that
/// undo can reverse.
struct Workspace: Sendable {
    static let base = FileManager.default.temporaryDirectory.appendingPathComponent("Zipboy", isDirectory: true)

    let folder: URL
    var contents: URL { folder.appendingPathComponent("Contents", isDirectory: true) }
    private var holding: URL { folder.appendingPathComponent("Holding", isDirectory: true) }

    init() throws {
        folder = Self.base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)
    }

    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func removeAbandoned() {
        try? FileManager.default.removeItem(at: base)
    }

    /// A fresh place in the holding area for an item called `name`.
    func holdingSpot(for name: String) throws -> URL {
        let slot = holding.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        return slot.appendingPathComponent(name)
    }

    /// A copy of the contents as they are now, for saving while editing carries on. On APFS it is a
    /// clone: instant, and taking no space until either side changes.
    func snapshot() throws -> URL {
        let copy = folder.appendingPathComponent("Snapshot-\(UUID().uuidString)", isDirectory: true)
        if clonefile(contents.path, copy.path, 0) != 0 {
            try FileManager.default.copyItem(at: contents, to: copy)
        }
        return copy
    }

    func url(_ path: String) -> URL {
        path.isEmpty ? contents : contents.appendingPathComponent(path)
    }
}

/// One rename inside a workspace.
struct Move: Sendable {
    var from: URL
    var to: URL

    var inverted: Move { Move(from: to, to: from) }

    /// rename(2), not FileManager, so that changing only the case of a name works on a case-insensitive
    /// volume.
    func perform() throws {
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard rename(from.path, to.path) == 0 else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [
                    NSFilePathErrorKey: from.path,
                    NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO),
                ])
        }
    }
}
