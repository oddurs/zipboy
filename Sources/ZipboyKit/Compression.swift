import Foundation

public enum ZipMethod: Equatable, Sendable {
    case store
    case deflate

    /// Deflating a file that is already compressed costs time and saves nothing, so these are stored.
    public static func forFile(named name: String) -> ZipMethod {
        precompressed.contains((name as NSString).pathExtension.lowercased()) ? .store : .deflate
    }

    static let precompressed: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "avif", "jxl",
        "mp4", "mov", "m4v", "mkv", "webm", "mp3", "m4a", "aac", "ogg", "opus", "flac",
        "zip", "zipx", "cbz", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma", "tlz",
        "zst", "tzst", "z", "taz", "lz4", "lzo", "7z", "cb7", "rar", "cbr", "cab", "lha", "lzh",
        "cpgz", "xar", "pkg", "deb", "rpm", "dmg",
        "docx", "xlsx", "pptx", "pages", "numbers", "key", "epub", "jar", "war", "ear",
        "apk", "ipa", "whl", "xpi", "nupkg", "woff", "woff2", "br",
    ]

    /// Extensions Zipboy opens as archives rather than compressing into a new archive when dropped on
    /// the Dock icon, even on systems where LaunchServices has not registered a dedicated UTI.
    public static let archiveExtensions: Set<String> = [
        "zip", "zipx", "cbz", "jar", "war", "ear", "apk", "ipa", "whl", "xpi", "nupkg",
        "rar", "cbr", "r00", "r01", "7z", "cb7", "z01", "001", "002",
        "tar", "tgz", "tbz", "tbz2", "txz", "tlz", "taz", "cbt",
        "gz", "bz2", "xz", "lzma", "z", "uu",
        "cpio", "cpgz", "iso", "cab", "lha", "lzh", "ar", "deb", "xar", "pkg",
    ]
}
