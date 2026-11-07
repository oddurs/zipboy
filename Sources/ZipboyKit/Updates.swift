import CryptoKit
import Foundation

/// Finding out there's a newer Zipboy, from the project's GitHub releases. No dependency: a release
/// is a tag, a DMG, and the DMG's SHA-256, which `scripts/task package` makes and the release workflow
/// attaches.
public enum Updates {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let page: URL
        public let disk: URL
        public let checksum: URL
    }

    /// Where the newest release that isn't a prerelease is described.
    public static let feed = URL(string: "https://api.github.com/repos/oddurs/zipboy/releases/latest")!

    /// The release in GitHub's description of one, if it carries the DMG and its checksum.
    public static func release(from json: Data) -> Release? {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: json), payload.draft != true,
            payload.prerelease != true
        else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        guard let disk = payload.assets.first(where: { $0.name == "Zipboy-\(version).dmg" }),
            let sum = payload.assets.first(where: { $0.name == "Zipboy-\(version).dmg.sha256" })
        else { return nil }
        return Release(
            version: version, page: payload.html_url, disk: disk.browser_download_url,
            checksum: sum.browser_download_url)
    }

    /// Whether `remote` is a later version than `local`, by semantic-version precedence. A local build
    /// between tags is stamped "<next version>-dev", so the previous release ranks below it and the next
    /// release ranks above it.
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        compare(remote, local) == .orderedDescending
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func split(_ version: String) -> (core: [Int], pre: [String]) {
            let parts = version.split(separator: "-", maxSplits: 1)
            let core = parts[0].split(separator: ".").map { Int($0) ?? 0 }
            return (
                core + Array(repeating: 0, count: max(0, 3 - core.count)),
                parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
            )
        }
        let (x, y) = (split(a), split(b))
        for (p, q) in zip(x.core, y.core) where p != q { return p < q ? .orderedAscending : .orderedDescending }
        // A release outranks any prerelease of the same version.
        switch (x.pre.isEmpty, y.pre.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        for (p, q) in zip(x.pre, y.pre) where p != q {
            if let m = Int(p), let n = Int(q) { return m < n ? .orderedAscending : .orderedDescending }
            return p < q ? .orderedAscending : .orderedDescending
        }
        return x.pre.count == y.pre.count
            ? .orderedSame : x.pre.count < y.pre.count ? .orderedAscending : .orderedDescending
    }

    /// Whether the downloaded disk image is the one the release describes: its SHA-256 against the
    /// published `.sha256` file, which reads "<hex>  Zipboy-<version>.dmg".
    public static func matches(_ disk: URL, checksumFile: String) -> Bool {
        guard let expected = checksumFile.split(whereSeparator: \.isWhitespace).first?.lowercased(),
            expected.count == 64, let handle = try? FileHandle(forReadingFrom: disk)
        else { return false }
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected
    }
}
