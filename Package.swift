// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zipboy",
    platforms: [.macOS(.v14)],
    targets: [
        // macOS ships libarchive but not its header, so the module declares the part we call.
        .systemLibrary(name: "CArchive"),
        .target(name: "ZipboyKit", dependencies: ["CArchive"]),
        .executableTarget(
            name: "Zipboy",
            dependencies: ["ZipboyKit"],
            linkerSettings: [
                .linkedFramework("Quartz"), .linkedFramework("CoreServices"),
                .linkedFramework("QuickLookThumbnailing"),
            ]
        ),
        // Finder's Quick Look preview. An app extension starts in NSExtensionMain, not main.
        .executableTarget(
            name: "ZipboyQuickLook",
            dependencies: ["ZipboyKit"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("QuickLookUI"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),
        // Finder's icon for an archive, built the same way.
        .executableTarget(
            name: "ZipboyThumbnail",
            dependencies: ["ZipboyKit"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("QuickLookThumbnailing"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),
        // Timing budgets, run by scripts/bench in a release build rather than in the test suite.
        .executableTarget(name: "ZipboyBench", dependencies: ["ZipboyKit"]),
        .testTarget(name: "ZipboyKitTests", dependencies: ["ZipboyKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ZipboyTests", dependencies: ["Zipboy"]),
    ]
)
