import Foundation
import Testing
import UniformTypeIdentifiers
import ZipboyKit

@testable import Zipboy

/// What scripts/task assembles into the app bundle, checked against the source tree.
@Suite struct BundleTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    static func source(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/Zipboy/\(name)"), encoding: .utf8)
    }

    @Test func namesTheApp() throws {
        let info = try Self.infoPlist()
        #expect(info["CFBundleName"] as? String == "Zipboy")
        #expect(info["CFBundleIdentifier"] as? String == "com.oddurs.zipboy")
        // scripts/task copies the SwiftPM product of this name into the bundle.
        #expect(info["CFBundleExecutable"] as? String == "Zipboy")
    }

    @Test func documentTypesNameTheDocumentClass() throws {
        let types = try #require(Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        // A class name AppKit can't find opens nothing, with no error anywhere.
        #expect(try Self.source("ArchiveDocument.swift").contains("@objc(ArchiveDocument)"))
        for type in types where type["NSDocumentClass"] != nil {
            #expect(type["NSDocumentClass"] as? String == "ArchiveDocument")
        }
        // Only the catch-all for the Dock icon has none, and it must never become anyone's default.
        let catchAll = types.filter { $0["NSDocumentClass"] == nil }
        #expect(catchAll.count == 1)
        #expect(catchAll.first?["LSHandlerRank"] as? String == "None")
    }

    @Test func writesOnlyZip() throws {
        let types = try #require(Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let editors = types.filter { $0["CFBundleTypeRole"] as? String == "Editor" }
        // The first Editor type is what File > New makes and what every archive saves as.
        #expect(editors.count == 1)
        #expect(editors.first?["LSItemContentTypes"] as? [String] == ["public.zip-archive"])
        #expect(try Self.source("ArchiveDocument.swift").contains("zipType = \"public.zip-archive\""))
    }

    @Test func zipsZipboyOwnsGetADocumentIconMadeFromMugi() throws {
        let types = try #require(Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        // The system draws the app icon onto a document page, so the type it writes, and only that,
        // reads as Zipboy's once Zipboy opens ZIPs. Types it only imports keep their own icons.
        for type in types {
            let owned = type["CFBundleTypeRole"] as? String == "Editor"
            #expect(
                (type["CFBundleTypeIconSystemGenerated"] as? Int == 1) == owned, "\(type["CFBundleTypeName"] ?? "")")
        }
    }

    @Test func declaresRarSinceMacOSDoesNot() throws {
        let types = try #require(Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let viewed = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(viewed.contains("com.rarlab.rar-archive"))
        let imported = try #require(Self.infoPlist()["UTImportedTypeDeclarations"] as? [[String: Any]])
        #expect(imported.contains { $0["UTTypeIdentifier"] as? String == "com.rarlab.rar-archive" })
    }

    @Test(arguments: [
        ("QuickLook", "ZipboyQuickLook", "PreviewProvider", "com.apple.quicklook.preview"),
        ("Thumbnail", "ZipboyThumbnail", "ThumbnailProvider", "com.apple.quicklook.thumbnail"),
    ])
    func eachQuickLookExtensionCoversOnlyWhatTheAppOpens(
        folder: String, executable: String, provider: String, point: String
    ) throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Resources/\(folder)/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ext = try #require(info["NSExtension"] as? [String: Any])
        // An extension's identifier must sit under its app's, or the system won't load it.
        #expect((info["CFBundleIdentifier"] as? String)?.hasPrefix("com.oddurs.zipboy.") == true)
        // scripts/task copies the SwiftPM product of this name, and finds the plist by the folder.
        #expect(info["CFBundleExecutable"] as? String == executable)
        #expect(executable == "Zipboy\(folder)")
        #expect(ext["NSExtensionPointIdentifier"] as? String == point)
        // The class Quick Look instantiates, by its Objective-C name.
        let source = try String(
            contentsOf: Self.root.appendingPathComponent("Sources/\(executable)/\(provider).swift"), encoding: .utf8)
        #expect(source.contains("@objc(\(try #require(ext["NSExtensionPrincipalClass"] as? String)))"))

        let attributes = try #require(ext["NSExtensionAttributes"] as? [String: Any])
        let covered = try #require(attributes["QLSupportedContentTypes"] as? [String])
        let types = try #require(Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let opened = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        for type in covered { #expect(opened.contains(type), "\(type) is covered but the app can't open it") }
    }

    @Test func theScriptingDictionaryNamesItsCommands() throws {
        let info = try Self.infoPlist()
        #expect(info["NSAppleScriptEnabled"] as? Bool == true)
        let name = try #require(info["OSAScriptingDefinition"] as? String)
        let sdef = try String(contentsOf: Self.root.appendingPathComponent("Resources/\(name)"), encoding: .utf8)
        let source = try Self.source("Scripting.swift")
        // A class name Cocoa scripting can't find makes the command fail with no hint why.
        let classes = sdef.matches(of: /<cocoa class="(\w+)"/).map { String($0.1) }
        #expect(classes == ["ZipboyExtractCommand", "ZipboyCompressCommand"])
        for name in classes { #expect(source.contains("@objc(\(name))")) }
        // scripts/task copies the dictionary into the bundle beside the icon.
        let task = try String(contentsOf: Self.root.appendingPathComponent("scripts/task"), encoding: .utf8)
        #expect(task.contains("Resources/\(name)"))
    }

    @Test func shipsMugi() throws {
        let task = try String(contentsOf: Self.root.appendingPathComponent("scripts/task"), encoding: .utf8)
        // The dark icon the running app switches to, and the poses the About window and welcome show.
        #expect(task.contains("Resources/AppIconDark.icns"))
        #expect(task.contains("cp -R Resources/Mugi"))
        for name in ["AppIcon.icns", "AppIconDark.icns", "Icon/mugi-v05-light.png", "Icon/mugi-v05-dark.png"]
            + ["neutral", "welcome", "presenting", "celebrate"].map({ "Mugi/\($0).png" })
        {
            #expect(
                FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Resources/\(name)").path),
                "\(name)")
        }
    }

    @Test func registersItsHelpBook() throws {
        let info = try Self.infoPlist()
        // Help Viewer finds the book by this pair: the folder in Resources, and the book's identifier.
        #expect(info["CFBundleHelpBookFolder"] as? String == "Zipboy.help")
        #expect(info["CFBundleHelpBookName"] as? String == HelpTopics.bookIdentifier)
        let task = try String(contentsOf: Self.root.appendingPathComponent("scripts/task"), encoding: .utf8)
        #expect(task.contains("ZipboyHelpBook"))
        #expect(task.contains("hiutil -I corespotlight") && task.contains("hiutil -I lsm"))
    }

    @Test func shipsItsIcon() throws {
        let name = try #require(Self.infoPlist()["CFBundleIconFile"] as? String)
        #expect(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Resources/\(name).icns").path))
    }

    @MainActor
    @Test func everyDeclaredExtensionHasAPassingFixture() throws {
        let info = try Self.infoPlist()
        let docTypes = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let imported = info["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
        var importedExtensions: [String: [String]] = [:]
        for item in imported {
            guard let id = item["UTTypeIdentifier"] as? String else { continue }
            let tags = item["UTTypeTagSpecification"] as? [String: Any]
            importedExtensions[id] = tags?["public.filename-extension"] as? [String] ?? []
        }

        var openedTypes = Set<String>()
        var declaredExtensions = Set(ZipMethod.archiveExtensions.map { $0.lowercased() })
        for doc in docTypes where doc["NSDocumentClass"] != nil {
            for id in doc["LSItemContentTypes"] as? [String] ?? [] {
                openedTypes.insert(id)
                guard id != "public.archive" else { continue }
                let exts = Set((UTType(id)?.tags[.filenameExtension] ?? []) + (importedExtensions[id] ?? []))
                    .map { $0.lowercased() }
                #expect(!exts.isEmpty, "\(id) declares no filename extensions")
                declaredExtensions.formUnion(exts)
            }
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipboyBundleFixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        func canExtract(_ file: URL, into out: URL) -> Bool {
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            do {
                _ = try Archive.extract(file, into: out)
                return true
            } catch ArchiveError.passwordRequired {
                return (try? Archive.extract(file, into: out, password: "secret")) != nil
            } catch {
                return false
            }
        }

        let matrix = Self.root.appendingPathComponent("Tests/ZipboyKitTests/Fixtures/matrix")
        let matrixFiles = try FileManager.default.contentsOfDirectory(at: matrix, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var passingFixtures: [URL] = []
        for (index, file) in matrixFiles.enumerated()
        where canExtract(file, into: scratch.appendingPathComponent("matrix-\(index)")) {
            passingFixtures.append(file)
        }

        // Standard container/filter aliases that share the exact wire format of a fixture in the matrix.
        let canonicalSuffix: [String: String] = [
            "zipx": "zip", "cbz": "zip", "jar": "zip", "war": "zip", "ear": "zip",
            "ipa": "zip", "apk": "zip", "whl": "zip", "xpi": "zip", "nupkg": "zip",
            "cbr": "rar",
            "cb7": "7z",
            "cbt": "tar",
            "tgz": "tar.gz", "gzip": "gz",
            "tbz": "tar.bz2", "tbz2": "tar.bz2", "bz": "bz2",
            "txz": "tar.xz",
            "tlz": "tar.lzma",
            "taz": "tar.z",
            "pax": "cpio",
            "iso": "iso.gz",
            "lzh": "lha",
            "deb": "ar",
            "pkg": "xar", "mpkg": "xar",
        ]

        let controller = DocumentController()
        for ext in declaredExtensions.sorted() {
            let suffix = canonicalSuffix[ext] ?? ext
            guard
                let fixture = passingFixtures.first(where: { $0.lastPathComponent.lowercased().hasSuffix(".\(suffix)") }
                )
            else {
                Issue.record("No passing fixture in Fixtures/matrix covers .\(ext)")
                continue
            }
            let sample = scratch.appendingPathComponent("sample.\(ext)")
            try? FileManager.default.removeItem(at: sample)
            try FileManager.default.copyItem(at: fixture, to: sample)
            let docType = try controller.typeForContents(of: sample)
            #expect(openedTypes.contains(docType), ".\(ext) mapped to undeclared document type \(docType)")
            #expect(canExtract(sample, into: scratch.appendingPathComponent("ext-\(ext)")), ".\(ext) failed to extract")
        }
    }

    @Test func stampsReleaseTagsAndNextDevVersionsWithCommitCount() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipboyVersionRepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        func git(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repo.path] + args
            process.environment = [
                "GIT_AUTHOR_NAME": "Test",
                "GIT_AUTHOR_EMAIL": "test@example.com",
                "GIT_COMMITTER_NAME": "Test",
                "GIT_COMMITTER_EMAIL": "test@example.com",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }

        func stamped() throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [Self.root.appendingPathComponent("scripts/task").path, "version", repo.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try git("init")
        try git("commit", "--allow-empty", "-m", "chore: initial")
        #expect(try stamped() == "0.1.0-dev 1")

        try git("tag", "v0.1.0-rc.1")
        #expect(try stamped() == "0.1.0-rc.1 1")

        try git("commit", "--allow-empty", "-m", "feat: past rc")
        #expect(try stamped() == "0.1.0-dev 2")

        try git("tag", "v0.1.0")
        #expect(try stamped() == "0.1.0 2")

        try git("commit", "--allow-empty", "-m", "feat: past 0.1.0")
        #expect(try stamped() == "0.1.1-dev 3")

        try git("tag", "v0.2.0")
        #expect(try stamped() == "0.2.0 3")

        try git("commit", "--allow-empty", "-m", "feat: past 0.2.0")
        #expect(try stamped() == "0.2.1-dev 4")

        let task = try String(contentsOf: Self.root.appendingPathComponent("scripts/task"), encoding: .utf8)
        #expect(task.contains("Set :CFBundleShortVersionString $short_ver"))
        #expect(task.contains("Set :CFBundleVersion $build_num"))
        #expect(try Self.source("AboutWindowController.swift").contains(#""Version \(short) (\(build))""#))
    }

    @Test func benchPrintsMeasurementsExitsOverBudgetAndHasNightlyWorkflow() throws {
        let fm = FileManager.default
        let budgetsURL = Self.root.appendingPathComponent("scripts/budgets.json")
        let budgetsRaw = try Data(contentsOf: budgetsURL)
        let entries = try #require(try JSONSerialization.jsonObject(with: budgetsRaw) as? [[String: Any]])
        let ids = Set(entries.compactMap { $0["id"] as? String })
        #expect(
            ids.isSuperset(of: [
                "open_5gb", "list_5gb", "list_100k", "delta_save_5gb", "full_save_5gb", "checksums_8mb",
                "quicklook_10k",
            ]))

        let benchBin = Bundle(for: ArchiveDocument.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ZipboyBench")
        #expect(fm.isExecutableFile(atPath: benchBin.path))

        func runBench(_ args: [String]) throws -> (Int32, String) {
            let p = Process()
            p.executableURL = benchBin
            p.currentDirectoryURL = Self.root
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            p.waitUntilExit()
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (p.terminationStatus, text)
        }

        let (selfStatus, selfOut) = try runBench(["--self-test"])
        #expect(selfStatus == 0, "\(selfOut)")
        #expect(selfOut.contains("self-test ok"))

        let (passStatus, passOut) = try runBench(["--only", "checksums_8mb"])
        #expect(passStatus == 0, "\(passOut)")
        #expect(passOut.contains("CRC-32 and SHA-256 of 8 MB"))
        #expect(passOut.contains("budget    300 ms  ok"))

        let tmp = fm.temporaryDirectory.appendingPathComponent("bench-over-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: tmp) }
        try Data(
            """
            [{"id": "checksums_8mb", "name": "CRC-32 and SHA-256 of 8 MB", "milliseconds": 0.001}]
            """.utf8
        ).write(to: tmp)

        let (failStatus, failOut) = try runBench(["--budgets", tmp.path, "--only", "checksums_8mb"])
        #expect(failStatus != 0, "\(failOut)")
        #expect(failOut.contains("OVER"))
        #expect(failOut.contains("over budget by more than 20%"))

        let workflow = try String(
            contentsOf: Self.root.appendingPathComponent(".github/workflows/bench.yml"), encoding: .utf8)
        #expect(workflow.contains("schedule:"))
        #expect(workflow.contains("cron:"))
        #expect(workflow.contains("scripts/bench"))
        #expect(workflow.contains("actions/upload-artifact@"))
    }
}
