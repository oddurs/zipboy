import Foundation

public enum Naming {
    /// Finder's "Keep Both" name: `photo.jpg` becomes `photo 2.jpg`, and `photo 2.jpg` becomes
    /// `photo 3.jpg`. Folders have no extension to keep. `taken` is compared without case, as APFS does.
    public static func unique(_ name: String, isDirectory: Bool, taken: Set<String>) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        guard lowered.contains(name.lowercased()) else { return name }

        let ext = isDirectory ? "" : (name as NSString).pathExtension
        var base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var number = 2
        if let space = base.lastIndex(of: " "), let n = Int(base[base.index(after: space)...]), n >= 2 {
            base = String(base[..<space])
            number = n + 1
        }
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !lowered.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }
}
