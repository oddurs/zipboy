import Foundation
import Testing

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

    @Test func shipsItsIcon() throws {
        let name = try #require(Self.infoPlist()["CFBundleIconFile"] as? String)
        #expect(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Resources/\(name).icns").path))
    }
}
