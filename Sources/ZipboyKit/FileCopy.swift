import Darwin
import Foundation

/// Copies files and folders the way Finder does, but in a way that can report and be stopped: by
/// bytes, through copyfile(3). On APFS each file is cloned, which is instant and reports nothing.
public enum FileCopy {
    /// The bytes `urls` hold, counting everything inside folders, for a progress bar's total.
    public static func size(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                total += fileSize(url)
                continue
            }
            let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            while let item = items?.nextObject() as? URL { total += fileSize(item) }
        }
        return total
    }

    /// Copies `source` (a file or folder) to `destination`, which must not exist. `progress` hears the
    /// bytes copied so far and returns false to stop, in which case whatever was written of
    /// `destination` is removed and `ArchiveError.cancelled` is thrown. `clone` lets a test force real
    /// copying, which is the only kind that reports.
    public static func copy(
        _ source: URL, to destination: URL, clone: Bool = true, progress: @escaping (Int64) -> Bool
    ) throws {
        // COPYFILE_EXCL alone lets a clone report success without copying, so the check is made here,
        // without following a link that may sit at the destination.
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let box = Box(progress)
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let context = Unmanaged.passUnretained(box).toOpaque()
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), context)
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        var flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL)
        if clone { flags |= copyfile_flags_t(COPYFILE_CLONE) }
        let status = withExtendedLifetime(box) { copyfile(source.path, destination.path, state, flags) }
        if box.stopped {
            try? FileManager.default.removeItem(at: destination)
            throw ArchiveError.cancelled
        }
        guard status == 0, box.failure == nil else {
            let code = box.failure ?? errno
            try? FileManager.default.removeItem(at: destination)
            throw CocoaError(
                .fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
        _ = progress(box.done)
    }

    private final class Box {
        let progress: (Int64) -> Bool
        /// Bytes of the files finished so far, to which the current file's count is added.
        var finished: Int64 = 0
        var current: Int64 = 0
        var stopped = false
        /// The errno of a file that failed; copyfile would otherwise skip it and report success.
        var failure: Int32?
        var done: Int64 { finished + current }
        init(_ progress: @escaping (Int64) -> Bool) { self.progress = progress }
    }

    private static let callback: copyfile_callback_t = { what, stage, state, source, destination, context in
        guard let context else { return COPYFILE_CONTINUE }
        let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
        if stage == COPYFILE_ERR || what == COPYFILE_RECURSE_ERROR {
            box.failure = errno == 0 ? EIO : errno
            return COPYFILE_QUIT
        }
        if what == COPYFILE_RECURSE_DIR, stage == COPYFILE_FINISH, let destination {
            // A read-only folder arrives read-only before its contents do, which then can't be written
            // into. Its owner may always write it; copyfile puts the original mode back when it's done.
            var info = stat()
            if lstat(destination, &info) == 0 { chmod(destination, info.st_mode | S_IRWXU) }
            return COPYFILE_CONTINUE
        }
        if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            box.current = Int64(copied)
        } else if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH, let source {
            box.finished += fileSize(URL(fileURLWithPath: String(cString: source)))
            box.current = 0
        } else {
            return COPYFILE_CONTINUE
        }
        guard box.progress(box.done) else {
            box.stopped = true
            return COPYFILE_QUIT
        }
        return COPYFILE_CONTINUE
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        return values?.isRegularFile == true ? Int64(values?.fileSize ?? 0) : 0
    }
}
