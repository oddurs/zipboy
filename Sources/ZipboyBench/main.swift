import Foundation
import ZipboyKit

// The performance budgets, measured in a release build away from the test suite, where a busy
// machine made them fail for reasons that weren't bugs. Run with `scripts/bench`.

struct Budget {
    let name: String
    let milliseconds: Double
}

var over: [String] = []

/// Runs `work` a few times and keeps the fastest, which is the least disturbed by whatever else
/// the machine is doing.
@MainActor
func measure(_ budget: Budget, runs: Int = 5, _ work: () throws -> Void) rethrows {
    var best = Double.infinity
    for _ in 0..<runs {
        let start = ContinuousClock.now
        try work()
        best = min(best, start.duration(to: .now) / .milliseconds(1))
    }
    let verdict = best <= budget.milliseconds * 1.2 ? "ok" : "OVER"
    if verdict == "OVER" { over.append(budget.name) }
    let line = [
        budget.name.padding(toLength: 34, withPad: " ", startingAt: 0),
        String(format: "%8.1f ms", best), String(format: "budget %6.0f ms", budget.milliseconds), verdict,
    ]
    print(line.joined(separator: "  "))
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipboyBench-\(UUID().uuidString)")
let src = dir.appendingPathComponent("src")
try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
try Data((0..<(8 << 20)).map { UInt8(($0 * 131) & 0xff) }).write(to: src.appendingPathComponent("large.bin"))
for index in 0..<200 { try Data("entry-\(index)".utf8).write(to: src.appendingPathComponent("file-\(index).txt")) }
let zip = dir.appendingPathComponent("bench.zip")
try Archive.writeZip(from: src, to: zip, compressionLevel: .fast)

try measure(Budget(name: "ZIP catalog, 201 entries", milliseconds: 250)) { _ = try ZipCatalog.read(from: zip) }

let catalog = try ZipCatalog.read(from: zip)
let edited = dir.appendingPathComponent("edited.txt")
try Data("updated-entry".utf8).write(to: edited)
let items: [ZipWriter.Item] =
    catalog.entries.filter { $0.path != "file-0.txt" }.map { .verbatim($0, newPath: nil) }
    + [.workspace(url: edited, path: "file-0.txt")]
try measure(Budget(name: "Delta save, 8 MB kept, 1 file new", milliseconds: 500)) {
    let out = dir.appendingPathComponent("delta-\(UUID().uuidString).zip")
    try ZipWriter.write(items: items, sourceZip: zip, to: out, compressionLevel: .balanced)
}

try measure(Budget(name: "CRC-32 and SHA-256 of 8 MB", milliseconds: 300)) {
    _ = try Checksums.compute(for: src.appendingPathComponent("large.bin"))
}

// Finder's Space bar: list and draw 10,000 entries (0031).
let many = dir.appendingPathComponent("many")
for folder in 0..<50 {
    try FileManager.default.createDirectory(
        at: many.appendingPathComponent("Folder \(folder)"), withIntermediateDirectories: true)
}
for index in 0..<10_000 {
    try Data().write(to: many.appendingPathComponent("Folder \(index % 50)/file \(index).txt"))
}
let manyZip = dir.appendingPathComponent("many.zip")
try Archive.writeZip(from: many, to: manyZip, compressionLevel: .fast)
try measure(Budget(name: "Quick Look preview, 10,000 entries", milliseconds: 300)) {
    let listing = try Archive.list(manyZip)
    _ = ArchivePreview.html(for: listing, name: "many.zip", fileSize: nil)
}

if !over.isEmpty {
    print("over budget by more than 20%: \(over.joined(separator: ", "))")
    exit(1)
}
