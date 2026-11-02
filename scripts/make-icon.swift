// Renders Resources/AppIcon.icns, Resources/AppIconDark.icns, and docs/icon.png from the approved
// Mugi V05 renders. Run: swift scripts/make-icon.swift
//
// The renders come from Mugi Atelier at 1024 px, the squircle filling the canvas. macOS icons sit
// inside a margin, 100 px a side at 1024, so the art is scaled into that grid at every size. Edit
// the renders in the designer and run this; never edit the .icns files.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func render(_ art: NSImage, side: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let margin = CGFloat(side) * 100 / 1024
    art.draw(in: NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: margin, dy: margin))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func icns(from source: String, to output: String) throws {
    let art = NSImage(contentsOf: root.appendingPathComponent(source))!
    let set = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: set) }
    for (points, scale) in sizes {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(art, side: points * scale).write(to: set.appendingPathComponent(name))
    }
    let tool = Process()
    tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    tool.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent(output).path]
    try tool.run()
    tool.waitUntilExit()
    guard tool.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    print("wrote \(output)")
}

try icns(from: "Resources/Icon/mugi-v05-light.png", to: "Resources/AppIcon.icns")
try icns(from: "Resources/Icon/mugi-v05-dark.png", to: "Resources/AppIconDark.icns")
try render(NSImage(contentsOf: root.appendingPathComponent("Resources/Icon/mugi-v05-light.png"))!, side: 512)
    .write(to: root.appendingPathComponent("docs/icon.png"))
print("wrote docs/icon.png")
