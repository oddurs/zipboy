import Foundation
import ZipboyKit

// The performance budgets, measured in a release build away from the test suite, where a busy
// machine made them fail for reasons that weren't bugs. Run with `scripts/bench`.

struct Budget: Decodable {
    let id: String
    let name: String
    let milliseconds: Double

    func isOver(measuredMilliseconds: Double) -> Bool {
        measuredMilliseconds > milliseconds * 1.2
    }
}

func parseArgs() -> (budgetsPath: String, only: String?, selfTest: Bool) {
    var budgetsPath = "scripts/budgets.json"
    var only: String?
    var selfTest = false
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--budgets" where index + 1 < args.count:
            budgetsPath = args[index + 1]
            index += 2
        case "--only" where index + 1 < args.count:
            only = args[index + 1]
            index += 2
        case "--self-test":
            selfTest = true
            index += 1
        default:
            fputs("usage: ZipboyBench [--budgets <file>] [--only <id>] [--self-test]\n", stderr)
            exit(2)
        }
    }
    return (budgetsPath, only, selfTest)
}

let options = parseArgs()
let budgetList = try JSONDecoder().decode(
    [Budget].self, from: Data(contentsOf: URL(fileURLWithPath: options.budgetsPath)))
let budgetsByID = Dictionary(uniqueKeysWithValues: budgetList.map { ($0.id, $0) })

func shouldRun(_ id: String) -> Bool {
    options.only == nil || options.only == id
}

func budget(_ id: String) -> Budget {
    guard let found = budgetsByID[id] else {
        fputs("missing budget '\(id)' in \(options.budgetsPath)\n", stderr)
        exit(2)
    }
    return found
}

if options.selfTest {
    let sample = Budget(id: "sample", name: "Sample", milliseconds: 100)
    precondition(!sample.isOver(measuredMilliseconds: 100.0))
    precondition(!sample.isOver(measuredMilliseconds: 120.0))
    precondition(sample.isOver(measuredMilliseconds: 120.1))
    print("self-test ok (\(budgetList.count) budgets loaded)")
    exit(0)
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
    let failed = budget.isOver(measuredMilliseconds: best)
    let verdict = failed ? "OVER" : "ok"
    if failed { over.append(budget.name) }
    let line = [
        budget.name.padding(toLength: 36, withPad: " ", startingAt: 0),
        String(format: "%8.1f ms", best),
        String(format: "budget %6.0f ms", budget.milliseconds),
        verdict,
    ]
    print(line.joined(separator: "  "))
    fflush(stdout)
}

let fm = FileManager.default
let cacheRoot = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["ZIPBOY_BENCH_CACHE"] ?? ".build/bench-fixtures/v1",
    isDirectory: true)
try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

let fiveGBZip = cacheRoot.appendingPathComponent("five-gb.zip")
let hundredKZip = cacheRoot.appendingPathComponent("hundred-k.zip")
let tenKZip = cacheRoot.appendingPathComponent("ten-k.zip")

let needsFiveGB =
    shouldRun("list_5gb") || shouldRun("open_5gb") || shouldRun("delta_save_5gb") || shouldRun("full_save_5gb")

// 1. Generate the 5 GB ZIP once if needed and not cached.
if needsFiveGB, ((try? fm.attributesOfItem(atPath: fiveGBZip.path)[.size] as? Int64) ?? 0) < 5_000_000_000 {
    print("==> generating 5 GB benchmark archive (cached at \(fiveGBZip.path))")
    fflush(stdout)
    let stage = cacheRoot.appendingPathComponent("stage-5gb-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: stage) }

    // Five 1,000,000,000-byte media files (stored) + 200 small text files (deflated) = 5.0 GB.
    let megabyte = Data((0..<(1 << 20)).map { UInt8(($0 &* 131 &+ 17) & 0xff) })
    var items: [ZipWriter.Item] = []
    for part in 0..<5 {
        let partURL = stage.appendingPathComponent("media-\(part).mp4")
        fm.createFile(atPath: partURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partURL)
        let fullChunks = 1_000_000_000 / megabyte.count
        let tailBytes = 1_000_000_000 % megabyte.count
        for _ in 0..<fullChunks { try handle.write(contentsOf: megabyte) }
        if tailBytes > 0 { try handle.write(contentsOf: megabyte.prefix(tailBytes)) }
        try handle.close()
        items.append(.workspace(url: partURL, path: "media/media-\(part).mp4"))
    }
    for index in 0..<200 {
        let noteURL = stage.appendingPathComponent("note-\(index).txt")
        try Data(String(repeating: "note-\(index)-line\n", count: 64).utf8).write(to: noteURL)
        items.append(.workspace(url: noteURL, path: "notes/note-\(index).txt"))
    }
    try ZipWriter.write(items: items, sourceZip: nil, to: fiveGBZip, compressionLevel: .fast)
}

// 2. Generate the 100,000-entry ZIP once if needed and not cached.
if shouldRun("list_100k"), !fm.fileExists(atPath: hundredKZip.path) {
    print("==> generating 100,000-entry benchmark archive (cached at \(hundredKZip.path))")
    fflush(stdout)
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
            &central, UInt32(0x0201_4b50), UInt16(0x032D), UInt16(20), UInt16(1 << 11), UInt16(0), dosTime, dosDate)
        appendLE(&central, UInt32(0), UInt32(0), UInt32(0), UInt16(name.count), UInt16(0), UInt16(0))
        appendLE(&central, UInt16(0), UInt16(0), UInt32(0o100644) << 16, offset)
        central.append(name)
    }
    let cdOffset = UInt64(local.count)
    let cdSize = UInt64(central.count)
    let z64Offset = cdOffset + cdSize
    var tail = Data()
    appendLE(&tail, UInt32(0x0606_4b50), UInt64(44), UInt16(0x032D), UInt16(45), UInt32(0), UInt32(0))
    appendLE(&tail, UInt64(count), UInt64(count), cdSize, cdOffset)
    appendLE(&tail, UInt32(0x0706_4b50), UInt32(0), z64Offset, UInt32(1))
    appendLE(
        &tail, UInt32(0x0605_4b50), UInt16(0), UInt16(0), UInt16(0xFFFF), UInt16(0xFFFF), UInt32(cdSize),
        UInt32(cdOffset), UInt16(0))
    let tmp = cacheRoot.appendingPathComponent("hundred-k-\(UUID().uuidString).tmp")
    fm.createFile(atPath: tmp.path, contents: nil)
    let out = try FileHandle(forWritingTo: tmp)
    try out.write(contentsOf: local)
    try out.write(contentsOf: central)
    try out.write(contentsOf: tail)
    try out.close()
    try? fm.removeItem(at: hundredKZip)
    try fm.moveItem(at: tmp, to: hundredKZip)
}

// 3. Generate the 10,000-entry Quick Look archive once if needed and not cached.
if shouldRun("quicklook_10k"), !fm.fileExists(atPath: tenKZip.path) {
    let many = cacheRoot.appendingPathComponent("stage-10k-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: many) }
    for folder in 0..<50 {
        try fm.createDirectory(at: many.appendingPathComponent("Folder \(folder)"), withIntermediateDirectories: true)
    }
    for index in 0..<10_000 {
        try Data().write(to: many.appendingPathComponent("Folder \(index % 50)/file \(index).txt"))
    }
    try Archive.writeZip(from: many, to: tenKZip, compressionLevel: .fast)
}

let scratch = fm.temporaryDirectory.appendingPathComponent("ZipboyBench-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }

if shouldRun("list_5gb") {
    try measure(budget("list_5gb")) {
        let parsed = try ZipCatalog.read(from: fiveGBZip)
        precondition(parsed.entries.count == 205)
    }
}

if shouldRun("list_100k") {
    try measure(budget("list_100k")) {
        let parsed = try ZipCatalog.read(from: hundredKZip)
        precondition(parsed.entries.count == 100_000)
    }
}

if shouldRun("delta_save_5gb") {
    let fiveGBCatalog = try ZipCatalog.read(from: fiveGBZip)
    let editedNote = scratch.appendingPathComponent("edited-note.txt")
    try Data("updated-single-file-in-five-gb-archive\n".utf8).write(to: editedNote)
    let deltaItems: [ZipWriter.Item] =
        fiveGBCatalog.entries.filter { $0.path != "notes/note-0.txt" }.map { .verbatim($0, newPath: nil) }
        + [.workspace(url: editedNote, path: "notes/note-0.txt")]
    let out = scratch.appendingPathComponent("delta-5gb.zip")
    defer { try? fm.removeItem(at: out) }

    try measure(budget("delta_save_5gb"), runs: 1) {
        try ZipWriter.write(items: deltaItems, sourceZip: fiveGBZip, to: out, compressionLevel: .balanced)
    }
}

let unpacked5GB = scratch.appendingPathComponent("unpacked-5gb", isDirectory: true)
if shouldRun("open_5gb") || shouldRun("full_save_5gb") {
    if shouldRun("open_5gb") {
        try measure(budget("open_5gb"), runs: 1) {
            try fm.createDirectory(at: unpacked5GB, withIntermediateDirectories: true)
            _ = try Archive.extract(fiveGBZip, into: unpacked5GB)
        }
    } else {
        try fm.createDirectory(at: unpacked5GB, withIntermediateDirectories: true)
        _ = try Archive.extract(fiveGBZip, into: unpacked5GB)
    }
}

if shouldRun("full_save_5gb") {
    let fullPaths = try Archive.contents(of: unpacked5GB)
    let fullItems: [ZipWriter.Item] = fullPaths.map { rel in
        .workspace(url: unpacked5GB.appendingPathComponent(rel), path: rel)
    }
    let out = scratch.appendingPathComponent("full-5gb.zip")
    defer { try? fm.removeItem(at: out) }
    try measure(budget("full_save_5gb"), runs: 1) {
        try ZipWriter.write(items: fullItems, sourceZip: nil, to: out, compressionLevel: .fast)
    }
    try? fm.removeItem(at: unpacked5GB)
} else {
    try? fm.removeItem(at: unpacked5GB)
}

if shouldRun("checksums_8mb") {
    let eightMB = scratch.appendingPathComponent("eight-mb.bin")
    try Data((0..<(8 << 20)).map { UInt8(($0 * 131) & 0xff) }).write(to: eightMB)
    try measure(budget("checksums_8mb")) {
        _ = try Checksums.compute(for: eightMB)
    }
}

if shouldRun("quicklook_10k") {
    try measure(budget("quicklook_10k")) {
        let listing = try Archive.list(tenKZip)
        _ = ArchivePreview.html(for: listing, name: "ten-k.zip", fileSize: nil)
    }
}

if !over.isEmpty {
    print("over budget by more than 20%: \(over.joined(separator: ", "))")
    exit(1)
}
