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

let hundredKZip = dir.appendingPathComponent("hundred-k.zip")
do {
    func appendLE<each T: FixedWidthInteger>(_ data: inout Data, _ values: repeat each T) {
        repeat data.append(contentsOf: Swift.withUnsafeBytes(of: (each values).littleEndian, Array.init))
    }
    let count = 100_000
    let dosDate: UInt16 = (46 << 9) | (11 << 5) | 7
    let dosTime: UInt16 = (12 << 11)
    var local = Data(capacity: count * 56)
    var central = Data(capacity: count * 72)
    for index in 0..<count {
        let name = Data("folder-\(index % 100)/entry-\(index).txt".utf8)
        let offset = UInt32(local.count)
        appendLE(&local, UInt32(0x0403_4b50), UInt16(20), UInt16(1 << 11), UInt16(0), dosTime, dosDate)
        appendLE(&local, UInt32(0), UInt32(0), UInt32(0), UInt16(name.count), UInt16(0))
        local.append(name)

        appendLE(
            &central, UInt32(0x0201_4b50), UInt16(0x031E), UInt16(20), UInt16(1 << 11), UInt16(0), dosTime, dosDate)
        appendLE(&central, UInt32(0), UInt32(0), UInt32(0), UInt16(name.count), UInt16(0), UInt16(0))
        appendLE(&central, UInt16(0), UInt16(0), UInt32(0o100644) << 16, offset)
        central.append(name)
    }
    let cdOffset = UInt64(local.count)
    let cdSize = UInt64(central.count)
    let z64Offset = cdOffset + cdSize
    var tail = Data()
    appendLE(&tail, UInt32(0x0606_4b50), UInt64(44), UInt16(45), UInt16(45), UInt32(0), UInt32(0))
    appendLE(&tail, UInt64(count), UInt64(count), cdSize, cdOffset)
    appendLE(&tail, UInt32(0x0706_4b50), UInt32(0), z64Offset, UInt32(1))
    appendLE(
        &tail, UInt32(0x0605_4b50), UInt16(0), UInt16(0), UInt16(0xFFFF), UInt16(0xFFFF), UInt32(cdSize),
        UInt32(cdOffset), UInt16(0))
    FileManager.default.createFile(atPath: hundredKZip.path, contents: nil)
    let out = try FileHandle(forWritingTo: hundredKZip)
    try out.write(contentsOf: local)
    try out.write(contentsOf: central)
    try out.write(contentsOf: tail)
    try out.close()
}
try measure(Budget(name: "ZIP catalog, 100,000 entries", milliseconds: 200)) {
    let parsed = try ZipCatalog.read(from: hundredKZip)
    precondition(parsed.entries.count == 100_000)
}

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
