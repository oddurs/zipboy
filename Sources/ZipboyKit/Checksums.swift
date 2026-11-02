import CryptoKit
import Foundation
import zlib

/// File digest computation (CRC-32 and SHA-256) in a single streaming pass.
public struct Checksums: Equatable, Sendable {
    public let crc32: UInt32
    public let crc32Hex: String
    public let sha256Hex: String

    public static func compute(for url: URL, chunkSize: Int = 256 * 1024) throws -> Checksums {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: uLong = zlib.crc32(0, nil, 0)
        var hasher = SHA256()
        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return }
                crc = zlib.crc32(crc, base, uInt(raw.count))
                hasher.update(bufferPointer: raw)
            }
        }
        let crcValue = UInt32(truncatingIfNeeded: crc)
        let crcHex = String(format: "%08X", crcValue)
        let digest = hasher.finalize()
        let shaHex = digest.map { String(format: "%02x", $0) }.joined()
        return Checksums(crc32: crcValue, crc32Hex: crcHex, sha256Hex: shaHex)
    }
}
