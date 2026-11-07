import Foundation
import Testing

@testable import ZipboyKit

struct UpdatesTests {
    func payload(tag: String, prerelease: Bool = false, assets: [String]? = nil) -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let names = assets ?? ["Zipboy-\(version).dmg", "Zipboy-\(version).dmg.sha256"]
        let list = names.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/oddurs/zipboy/releases/download/\#(tag)/\#($0)"}"#
        }
        return Data(
            #"""
            {"tag_name": "\#(tag)", "html_url": "https://github.com/oddurs/zipboy/releases/tag/\#(tag)",
             "draft": false, "prerelease": \#(prerelease), "assets": [\#(list.joined(separator: ","))]}
            """#.utf8)
    }

    @Test func readsAReleaseWithItsDiskAndChecksum() throws {
        let release = try #require(Updates.release(from: payload(tag: "v0.4.1")))
        #expect(release.version == "0.4.1")
        #expect(release.disk.lastPathComponent == "Zipboy-0.4.1.dmg")
        #expect(release.checksum.lastPathComponent == "Zipboy-0.4.1.dmg.sha256")
    }

    @Test func passesOverPrereleasesAndIncompleteReleases() {
        #expect(Updates.release(from: payload(tag: "v0.5.0-rc.1", prerelease: true)) == nil)
        #expect(Updates.release(from: payload(tag: "v0.4.1", assets: ["Zipboy-0.4.1.dmg"])) == nil)
        #expect(Updates.release(from: Data("not json".utf8)) == nil)
    }

    @Test(arguments: [
        ("0.4.1", "0.4.0", true), ("0.4.0", "0.4.0", false), ("0.4.0", "0.4.1", false),
        ("0.10.0", "0.9.9", true), ("0.4.0", "0.4.0-rc.2", true), ("0.4.0-rc.2", "0.4.0-rc.1", true),
        ("0.4.0-rc.1", "0.4.0", false), ("0.1.0", "0.1.0-dev", true), ("0.4.0", "0.4.1-dev", false),
        ("0.4.1", "0.4.1-dev", true), ("0.5.0", "0.4.1-dev", true),
    ])
    func comparesVersions(remote: String, local: String, newer: Bool) {
        #expect(Updates.isNewer(remote, than: local) == newer, "\(remote) vs \(local)")
    }

    @Test func aDiskImageMustMatchItsChecksum() throws {
        let disk = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString).dmg")
        try Data("disk image".utf8).write(to: disk)
        let good = "b5f0f2f9f2c0b9d84f6c4ad4b3d0b0d5d3f1ab2d3e5fd36d9cf9c1e7b6a1a0f2"
        let actual = try String(
            decoding: Process.run("/usr/bin/shasum", ["-a", "256", disk.path]), as: UTF8.self)
        #expect(Updates.matches(disk, checksumFile: actual))
        #expect(!Updates.matches(disk, checksumFile: "\(good)  Zipboy-0.4.1.dmg"))
        #expect(!Updates.matches(disk, checksumFile: "nonsense"))
    }
}

extension Process {
    static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
