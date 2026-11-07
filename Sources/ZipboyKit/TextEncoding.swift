import CoreFoundation
import Foundation

/// Legacy and modern filename encodings for archive entries that do not set the UTF-8 flag.
public enum TextEncoding: String, CaseIterable, Sendable {
    case auto
    case utf8
    case cp437
    case shiftJIS
    case gb18030
    case big5
    case eucKR
    case windows1251
    case windows1252

    public var title: String {
        switch self {
        case .auto: "Automatic"
        case .utf8: "Unicode (UTF-8)"
        case .cp437: "DOS Latin US (CP437)"
        case .shiftJIS: "Japanese (Shift-JIS)"
        case .gb18030: "Chinese Simplified (GB18030)"
        case .big5: "Chinese Traditional (Big5)"
        case .eucKR: "Korean (EUC-KR)"
        case .windows1251: "Cyrillic (Windows-1251)"
        case .windows1252: "Western (Windows-1252)"
        }
    }

    public var nsEncoding: String.Encoding? {
        switch self {
        case .auto:
            nil
        case .utf8:
            .utf8
        case .cp437:
            Self.encoding(from: .dosLatinUS)
        case .shiftJIS:
            .shiftJIS
        case .gb18030:
            Self.encoding(from: .GB_18030_2000)
        case .big5:
            Self.encoding(from: .big5)
        case .eucKR:
            Self.encoding(from: .EUC_KR)
        case .windows1251:
            .windowsCP1251
        case .windows1252:
            .windowsCP1252
        }
    }

    private static func encoding(from cf: CFStringEncodings) -> String.Encoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: raw)
    }

    /// Decodes a raw filename byte sequence using `self`, or auto-detecting when `.auto`.
    public func decode(_ data: Data, utf8Flagged: Bool = false) -> String {
        let isASCII = data.withUnsafeBytes { !$0.contains(where: { $0 >= 0x80 }) }
        if isASCII {
            return String(decoding: data, as: UTF8.self)
        }
        if utf8Flagged, let str = String(data: data, encoding: .utf8) {
            return str
        }
        switch self {
        case .auto:
            if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\u{FFFD}") {
                return utf8
            }
            let detected = Self.detect(for: [data])
            if detected != .auto, detected != .cp437, let ns = detected.nsEncoding,
                let decoded = String(data: data, encoding: ns)
            {
                return decoded
            }
            return Self.decodeCP437(data)
        case .cp437:
            return Self.decodeCP437(data)
        default:
            if let ns = nsEncoding, let decoded = String(data: data, encoding: ns) {
                return decoded
            }
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            return Self.decodeCP437(data)
        }
    }

    /// Inspects raw entry names across an archive to pick the most likely legacy encoding when
    /// entries are not valid UTF-8.
    public static func detect(for samples: [Data]) -> TextEncoding {
        let nonASCII = samples.filter { $0.contains(where: { $0 >= 0x80 }) }
        guard !nonASCII.isEmpty else { return .utf8 }
        if nonASCII.allSatisfy({ String(data: $0, encoding: .utf8) != nil }) {
            return .utf8
        }
        // Check multi-byte CJK encodings where every sample is valid in that encoding and has
        // multi-byte sequences characteristic of it.
        if nonASCII.allSatisfy({ isLikelyShiftJIS($0) && String(data: $0, encoding: .shiftJIS) != nil }) {
            return .shiftJIS
        }
        if let gb = TextEncoding.gb18030.nsEncoding,
            nonASCII.allSatisfy({ isLikelyGB18030($0) && String(data: $0, encoding: gb) != nil })
        {
            return .gb18030
        }
        if let kr = TextEncoding.eucKR.nsEncoding,
            nonASCII.allSatisfy({ isLikelyEUCKR($0) && String(data: $0, encoding: kr) != nil })
        {
            return .eucKR
        }
        if let b5 = TextEncoding.big5.nsEncoding,
            nonASCII.allSatisfy({ isLikelyBig5($0) && String(data: $0, encoding: b5) != nil })
        {
            return .big5
        }
        if nonASCII.allSatisfy({ isLikelyWindows1251($0) }) {
            return .windows1251
        }
        return .cp437
    }

    private static func isLikelyShiftJIS(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        var pairs = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if (0x81...0x9F).contains(b) || (0xE0...0xEF).contains(b) {
                guard i + 1 < bytes.count else { return false }
                let t = bytes[i + 1]
                guard (0x40...0x7E).contains(t) || (0x80...0xFC).contains(t) else { return false }
                // Single high byte 0x81 followed by ASCII in CP437 (like 0x81 'b' 'e' 'r' for "über")
                // has an ASCII second byte; in Shift-JIS 0x8140..0x81FC is punctuation, not letters,
                // so require either multiple DBCS pairs or a non-0x81 lead byte when followed by ASCII.
                if b == 0x81, (0x61...0x7A).contains(t), bytes.filter({ $0 >= 0x80 }).count == 1 {
                    return false
                }
                pairs += 1
                i += 2
            } else if (0xA1...0xDF).contains(b) {
                pairs += 1
                i += 1
            } else {
                return false
            }
        }
        return pairs > 0
    }

    private static func isLikelyGB18030(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        var pairs = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if (0xA1...0xF7).contains(b) {
                guard i + 1 < bytes.count else { return false }
                let t = bytes[i + 1]
                guard (0xA1...0xFE).contains(t) else { return false }
                pairs += 1
                i += 2
            } else {
                return false
            }
        }
        return pairs > 0
    }

    private static func isLikelyEUCKR(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        var pairs = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if (0xB0...0xC8).contains(b) {
                guard i + 1 < bytes.count, (0xA1...0xFE).contains(bytes[i + 1]) else { return false }
                pairs += 1
                i += 2
            } else {
                return false
            }
        }
        return pairs > 0
    }

    private static func isLikelyBig5(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        var pairs = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if (0xA4...0xF9).contains(b) {
                guard i + 1 < bytes.count else { return false }
                let t = bytes[i + 1]
                guard (0x40...0x7E).contains(t) || (0xA1...0xFE).contains(t) else { return false }
                pairs += 1
                i += 2
            } else {
                return false
            }
        }
        return pairs > 0
    }

    private static func isLikelyWindows1251(_ data: Data) -> Bool {
        let high = data.filter { $0 >= 0x80 }
        guard high.count >= 2 else { return false }
        return high.allSatisfy { (0xC0...0xFF).contains($0) || $0 == 0xA8 || $0 == 0xB8 }
    }

    /// Exact IBM PC Code Page 437 table for bytes 0x80...0xFF, matching PKWARE's traditional ZIP spec.
    public static func decodeCP437(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(data.count)
        for byte in data {
            if byte < 0x80 {
                scalars.append(UnicodeScalar(byte))
            } else {
                scalars.append(cp437Table[Int(byte - 0x80)])
            }
        }
        return String(scalars)
    }

    private static let cp437Table: [UnicodeScalar] = [
        "\u{00C7}", "\u{00FC}", "\u{00E9}", "\u{00E2}", "\u{00E4}", "\u{00E0}", "\u{00E5}", "\u{00E7}",
        "\u{00EA}", "\u{00EB}", "\u{00E8}", "\u{00EF}", "\u{00EE}", "\u{00EC}", "\u{00C4}", "\u{00C5}",
        "\u{00C9}", "\u{00E6}", "\u{00C6}", "\u{00F4}", "\u{00F6}", "\u{00F2}", "\u{00FB}", "\u{00F9}",
        "\u{00FF}", "\u{00D6}", "\u{00DC}", "\u{00A2}", "\u{00A3}", "\u{00A5}", "\u{20A7}", "\u{0192}",
        "\u{00E1}", "\u{00ED}", "\u{00F3}", "\u{00FA}", "\u{00F1}", "\u{00D1}", "\u{00AA}", "\u{00BA}",
        "\u{00BF}", "\u{2310}", "\u{00AC}", "\u{00BD}", "\u{00BC}", "\u{00A1}", "\u{00AB}", "\u{00BB}",
        "\u{2591}", "\u{2592}", "\u{2593}", "\u{2502}", "\u{2524}", "\u{2561}", "\u{2562}", "\u{2556}",
        "\u{2555}", "\u{2563}", "\u{2551}", "\u{2557}", "\u{255D}", "\u{255C}", "\u{255B}", "\u{2510}",
        "\u{2514}", "\u{2534}", "\u{252C}", "\u{251C}", "\u{2500}", "\u{253C}", "\u{255E}", "\u{255F}",
        "\u{255A}", "\u{2554}", "\u{2569}", "\u{2566}", "\u{2560}", "\u{2550}", "\u{256C}", "\u{2567}",
        "\u{2568}", "\u{2564}", "\u{2565}", "\u{2559}", "\u{2558}", "\u{2552}", "\u{2553}", "\u{256B}",
        "\u{256A}", "\u{2518}", "\u{250C}", "\u{2588}", "\u{2584}", "\u{258C}", "\u{2590}", "\u{2580}",
        "\u{03B1}", "\u{00DF}", "\u{0393}", "\u{03C0}", "\u{03A3}", "\u{03C3}", "\u{00B5}", "\u{03C4}",
        "\u{03A6}", "\u{0398}", "\u{03A9}", "\u{03B4}", "\u{221E}", "\u{03C6}", "\u{03B5}", "\u{2229}",
        "\u{2261}", "\u{00B1}", "\u{2265}", "\u{2264}", "\u{2320}", "\u{2321}", "\u{00F7}", "\u{2248}",
        "\u{00B0}", "\u{2219}", "\u{00B7}", "\u{221A}", "\u{207F}", "\u{00B2}", "\u{25A0}", "\u{00A0}",
    ]
}
