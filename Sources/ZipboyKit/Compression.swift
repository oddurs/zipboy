import Foundation

public enum ZipMethod: Equatable, Sendable {
    case store
    case deflate

    /// Deflating a file that is already compressed costs time and saves nothing, so these are stored.
    public static func forFile(named name: String) -> ZipMethod {
        precompressed.contains((name as NSString).pathExtension.lowercased()) ? .store : .deflate
    }

    static let precompressed: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "avif",
        "mp4", "mov", "m4v", "mkv", "webm", "mp3", "m4a", "aac", "ogg", "opus", "flac",
        "zip", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "dmg",
        "docx", "xlsx", "pptx", "pages", "numbers", "key", "epub", "jar", "apk", "ipa",
    ]
}
