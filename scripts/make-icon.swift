// Renders Resources/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
//
// A warm squircle with a zipper running down it, half open at the bottom where the pull sits.
import AppKit

func squircle(_ r: CGRect, n: CGFloat = 4.6) -> CGPath {
    // A superellipse, closer to Apple's continuous corners than a rounded rect.
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: a)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func draw(_ ctx: CGContext) {
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.32))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0xf08a1c))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    linear(ctx, [rgb(0xffc04a), rgb(0xf27d16), rgb(0xd9480f)], CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 100))

    // The tape on each side of the teeth, and the gap where the zip has come open.
    let top: CGFloat = 924, closedTo: CGFloat = 430, pullY: CGFloat = 380
    let gap = CGMutablePath()
    gap.move(to: CGPoint(x: 512, y: pullY))
    gap.addCurve(
        to: CGPoint(x: 400, y: 100), control1: CGPoint(x: 470, y: 300), control2: CGPoint(x: 410, y: 220))
    gap.addLine(to: CGPoint(x: 624, y: 100))
    gap.addCurve(
        to: CGPoint(x: 512, y: pullY), control1: CGPoint(x: 614, y: 220), control2: CGPoint(x: 554, y: 300))
    gap.closeSubpath()
    ctx.addPath(gap)
    ctx.setFillColor(rgb(0x5a1d06, 0.55))
    ctx.fillPath()

    // Interlocking teeth down the closed part: alternate sides, each a small rounded bar.
    let tooth = CGSize(width: 64, height: 26)
    var y = top - 20
    var left = true
    while y > closedTo {
        let x = left ? 512 - tooth.width + 8 : 512 - 8
        let rect = CGRect(x: x, y: y - tooth.height, width: tooth.width, height: tooth.height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.setFillColor(rgb(0xfff4e0))
        ctx.fillPath()
        y -= tooth.height + 6
        left.toggle()
    }

    // The slider and its pull tab.
    let slider = CGRect(x: 512 - 58, y: pullY - 10, width: 116, height: 80)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.35))
    ctx.addPath(CGPath(roundedRect: slider, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(rgb(0xffffff))
    ctx.fillPath()
    ctx.restoreGState()
    let tab = CGRect(x: 512 - 38, y: pullY - 190, width: 76, height: 200)
    let tabPath = CGPath(roundedRect: tab, cornerWidth: 38, cornerHeight: 38, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.3))
    ctx.addPath(tabPath)
    ctx.setFillColor(rgb(0xfffaf2))
    ctx.fillPath()
    ctx.restoreGState()
    let hole = CGRect(x: 512 - 16, y: pullY - 160, width: 32, height: 70)
    ctx.addPath(CGPath(roundedRect: hole, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(rgb(0xe0661a))
    ctx.fillPath()
    ctx.restoreGState()
}

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Zipboy-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.createDirectory(
    at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try render(512).write(to: root.appendingPathComponent("docs/icon.png"))
try FileManager.default.removeItem(at: iconset)
print("wrote Resources/AppIcon.icns and docs/icon.png")
