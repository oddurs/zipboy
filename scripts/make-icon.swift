// Renders Resources/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
//
// Zipboy: a manga boy in side profile sprinting across a warm orange squircle with speed streaks
// and a flying zipper pull tab.
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

func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    for (i, pt) in pts.enumerated() {
        let cg = CGPoint(x: pt.0, y: pt.1)
        i == 0 ? p.move(to: cg) : p.addLine(to: cg)
    }
    p.closeSubpath()
    return p
}

func fillAndStroke(
    _ ctx: CGContext, _ path: CGPath, fill: CGColor, stroke: CGColor, lineWidth: CGFloat = 15,
    join: CGLineJoin = .round
) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(lineWidth)
    ctx.setLineJoin(join)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func streak(
    _ ctx: CGContext, xLeft: CGFloat, xRight: CGFloat, y: CGFloat, thickness: CGFloat, peakRatio: CGFloat = 0.25,
    color: CGColor
) {
    // A razor-sharp manga speed line (koka-sen) tapering to needle tips at both ends.
    let p = CGMutablePath()
    let xPeak = xLeft + (xRight - xLeft) * peakRatio
    p.move(to: CGPoint(x: xLeft, y: y))
    p.addLine(to: CGPoint(x: xPeak, y: y + thickness * 0.5))
    p.addLine(to: CGPoint(x: xRight, y: y))
    p.addLine(to: CGPoint(x: xPeak, y: y - thickness * 0.5))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let ink = rgb(0x1f0e05)
let cream = rgb(0xfff7eb)
let skin = rgb(0xffdfc4)
let skinShade = rgb(0xf0b88d)
let jacket = rgb(0xfffaf2)
let jacketShade = rgb(0xf0d8bc)
let shorts = rgb(0x2b160a)
let gold = rgb(0xffd452)
let hotOrange = rgb(0xe8590c)

func drawSpeedBackground(_ ctx: CGContext) {
    // Deep manga action wedges cutting across the warm orange backdrop.
    let darkStreak = rgb(0x6e1d05, 0.36)
    let bands: [(CGFloat, CGFloat, CGFloat)] = [
        (862, 42, 780), (775, 28, 640), (695, 50, 720), (595, 26, 560),
        (500, 62, 670), (395, 34, 600), (298, 46, 710), (198, 36, 760),
    ]
    for (y, h, xEnd) in bands {
        streak(ctx, xLeft: 90, xRight: xEnd, y: y, thickness: h, peakRatio: 0.15, color: darkStreak)
    }

    // Unzipped zipper track wake trailing behind Zipboy's slider at mid-height.
    let trackY: CGFloat = 492
    let toothW: CGFloat = 24, toothH: CGFloat = 13
    for i in 0..<10 {
        let tx = 118 + CGFloat(i) * 30
        let spread = max(2, (395 - tx) * 0.15)
        let alpha = 0.30 + 0.55 * (tx - 110) / 300
        ctx.setFillColor(rgb(0xfff4e0, alpha))
        let upper = CGRect(x: tx, y: trackY + 5 + spread, width: toothW, height: toothH)
        let lower = CGRect(x: tx + 14, y: trackY - 5 - toothH - spread, width: toothW, height: toothH)
        ctx.addPath(CGPath(roundedRect: upper, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: lower, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
    }

    // Crisp bright manga speed streaks (koka-sen) shooting left behind Zipboy.
    let brightStreaks: [(CGFloat, CGFloat, CGFloat, CGFloat, CGColor)] = [
        (95, 520, 835, 22, rgb(0xfff9ed, 0.94)),
        (120, 390, 792, 13, rgb(0xffe599, 0.86)),
        (95, 455, 742, 27, rgb(0xfff9ed, 0.96)),
        (115, 360, 690, 14, rgb(0xffe599, 0.82)),
        (95, 415, 642, 20, rgb(0xfff9ed, 0.92)),
        (135, 330, 588, 12, rgb(0xffe599, 0.78)),
        (95, 375, 535, 25, rgb(0xfff9ed, 0.96)),
        (120, 310, 448, 15, rgb(0xffe599, 0.86)),
        (95, 345, 305, 22, rgb(0xfff9ed, 0.92)),
        (115, 450, 245, 16, rgb(0xffe599, 0.86)),
        (95, 525, 182, 24, rgb(0xfff9ed, 0.92)),
    ]
    for (x0, x1, y, th, col) in brightStreaks {
        streak(ctx, xLeft: x0, xRight: x1, y: y, thickness: th, peakRatio: 0.18, color: col)
    }

    // Thin manga ink speed lines for crisp graphic contrast.
    let inkLines: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (100, 465, 814, 10),
        (100, 385, 715, 11),
        (105, 340, 562, 10),
        (100, 310, 395, 10),
        (105, 480, 212, 10),
    ]
    for (x0, x1, y, th) in inkLines {
        streak(ctx, xLeft: x0, xRight: x1, y: y, thickness: th, peakRatio: 0.2, color: ink)
    }
}

func drawLimbsBehind(_ ctx: CGContext) {
    // Back arm (pumping backward and up behind the torso).
    let backArm = CGMutablePath()
    backArm.move(to: CGPoint(x: 515, y: 550))
    backArm.addLine(to: CGPoint(x: 390, y: 582))
    backArm.addLine(to: CGPoint(x: 320, y: 642))
    ctx.saveGState()
    ctx.addPath(backArm)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(72)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(backArm)
    ctx.setStrokeColor(jacketShade)
    ctx.setLineWidth(42)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Back fist.
    let backFist = CGPath(
        ellipseIn: CGRect(x: 278, y: 608, width: 68, height: 64), transform: nil)
    fillAndStroke(ctx, backFist, fill: skinShade, stroke: ink, lineWidth: 15)

    // Back leg kicking high to the left.
    let backLeg = CGMutablePath()
    backLeg.move(to: CGPoint(x: 455, y: 390))
    backLeg.addLine(to: CGPoint(x: 350, y: 315))
    backLeg.addLine(to: CGPoint(x: 238, y: 368))
    ctx.saveGState()
    ctx.addPath(backLeg)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(74)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(backLeg)
    ctx.setStrokeColor(skinShade)
    ctx.setLineWidth(44)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Back sneaker with rounded corners.
    let backShoe = CGMutablePath()
    backShoe.move(to: CGPoint(x: 252, y: 396))
    backShoe.addLine(to: CGPoint(x: 175, y: 425))
    backShoe.addQuadCurve(to: CGPoint(x: 155, y: 348), control: CGPoint(x: 145, y: 395))
    backShoe.addLine(to: CGPoint(x: 245, y: 332))
    backShoe.closeSubpath()
    fillAndStroke(ctx, backShoe, fill: hotOrange, stroke: ink, lineWidth: 15, join: .round)

    let backSole = CGMutablePath()
    backSole.move(to: CGPoint(x: 168, y: 412))
    backSole.addLine(to: CGPoint(x: 156, y: 358))
    ctx.saveGState()
    ctx.addPath(backSole)
    ctx.setStrokeColor(cream)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawZipperCapeTab(_ ctx: CGContext) {
    // Giant iconic zipper pull-tab streaming backward from the boy's collar like a manga scarf!
    ctx.saveGState()
    ctx.translateBy(x: 515, y: 540)
    ctx.rotate(by: 0.16)

    // Long pull tab flying left.
    let tab = CGPath(
        roundedRect: CGRect(x: -245, y: -40, width: 215, height: 80), cornerWidth: 38, cornerHeight: 38,
        transform: nil)
    let hole = CGPath(
        roundedRect: CGRect(x: -202, y: -16, width: 100, height: 32), cornerWidth: 16, cornerHeight: 16,
        transform: nil)
    let combined = CGMutablePath()
    combined.addPath(tab)
    combined.addPath(hole)

    ctx.addPath(combined)
    ctx.setFillColor(gold)
    ctx.fillPath(using: .evenOdd)

    ctx.addPath(tab)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(15)
    ctx.strokePath()

    ctx.addPath(hole)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(14)
    ctx.strokePath()

    // Slider body anchoring the pull tab at the shoulder/collar.
    let slider = CGPath(
        roundedRect: CGRect(x: -52, y: -30, width: 72, height: 60), cornerWidth: 18, cornerHeight: 18,
        transform: nil)
    fillAndStroke(ctx, slider, fill: cream, stroke: ink, lineWidth: 15)

    ctx.restoreGState()
}

func drawTorsoAndFrontLeg(_ ctx: CGContext) {
    // Front leg driving forward and down.
    let frontLeg = CGMutablePath()
    frontLeg.move(to: CGPoint(x: 490, y: 385))
    frontLeg.addLine(to: CGPoint(x: 655, y: 375))
    frontLeg.addLine(to: CGPoint(x: 585, y: 225))
    ctx.saveGState()
    ctx.addPath(frontLeg)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(76)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(frontLeg)
    ctx.setStrokeColor(skin)
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Shorts (dark manga athletic shorts).
    let shortPath = poly([
        (415, 420), (545, 430), (618, 355), (545, 315), (465, 345), (370, 305), (335, 365),
    ])
    fillAndStroke(ctx, shortPath, fill: shorts, stroke: ink, lineWidth: 15)

    // Front sneaker (chunky manga runner shoe).
    let shoe = CGMutablePath()
    shoe.move(to: CGPoint(x: 552, y: 245))
    shoe.addLine(to: CGPoint(x: 625, y: 242))
    shoe.addQuadCurve(to: CGPoint(x: 698, y: 185), control: CGPoint(x: 685, y: 225))
    shoe.addQuadCurve(to: CGPoint(x: 675, y: 152), control: CGPoint(x: 705, y: 155))
    shoe.addLine(to: CGPoint(x: 538, y: 168))
    shoe.closeSubpath()
    fillAndStroke(ctx, shoe, fill: hotOrange, stroke: ink, lineWidth: 15)

    // Thick white sneaker sole.
    let sole = CGMutablePath()
    sole.move(to: CGPoint(x: 545, y: 174))
    sole.addLine(to: CGPoint(x: 682, y: 160))
    ctx.saveGState()
    ctx.addPath(sole)
    ctx.setStrokeColor(cream)
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Torso: forward-leaning cream zip-hoodie.
    let torso = CGMutablePath()
    torso.move(to: CGPoint(x: 410, y: 405))
    torso.addQuadCurve(to: CGPoint(x: 505, y: 585), control: CGPoint(x: 440, y: 515))
    torso.addLine(to: CGPoint(x: 645, y: 555))
    torso.addQuadCurve(to: CGPoint(x: 555, y: 385), control: CGPoint(x: 615, y: 465))
    torso.closeSubpath()
    fillAndStroke(ctx, torso, fill: jacket, stroke: ink, lineWidth: 15)

    // Bold zipper track running up the jacket torso.
    ctx.saveGState()
    ctx.addPath(torso)
    ctx.clip()
    // Subtle back-side shading on the hoodie.
    let torsoShade = poly([(410, 405), (475, 400), (555, 575), (500, 585)])
    ctx.addPath(torsoShade)
    ctx.setFillColor(jacketShade)
    ctx.fillPath()

    let zipLine = CGMutablePath()
    zipLine.move(to: CGPoint(x: 505, y: 380))
    zipLine.addLine(to: CGPoint(x: 592, y: 575))
    ctx.addPath(zipLine)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(12)
    ctx.strokePath()

    // Interlocking gold teeth along the jacket's zipper.
    for i in 0..<5 {
        let t = CGFloat(i) / 4.5
        let zx = 510 + t * 65
        let zy = 398 + t * 140
        let offset: CGFloat = (i % 2 == 0) ? -14 : 4
        let toothRect = CGRect(x: zx + offset, y: zy, width: 22, height: 12)
        let toothPath = CGPath(roundedRect: toothRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(toothPath)
        ctx.setFillColor(gold)
        ctx.fillPath()
        ctx.addPath(toothPath)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(5)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawHead(_ ctx: CGContext) {
    // High sporty zip-collar in bright orange.
    let collar = poly([(495, 560), (648, 540), (662, 598), (488, 608)])
    fillAndStroke(ctx, collar, fill: hotOrange, stroke: ink, lineWidth: 15)

    // Side-profile manga face looking right, tilted forward for speed.
    let face = CGMutablePath()
    face.move(to: CGPoint(x: 695, y: 742))
    face.addQuadCurve(to: CGPoint(x: 726, y: 692), control: CGPoint(x: 715, y: 718))
    // Crisp anime nose in profile.
    face.addLine(to: CGPoint(x: 762, y: 672))
    face.addLine(to: CGPoint(x: 734, y: 650))
    // Upper lip & jaw down to chin.
    face.addLine(to: CGPoint(x: 740, y: 632))
    face.addQuadCurve(to: CGPoint(x: 708, y: 582), control: CGPoint(x: 734, y: 595))
    // Jawline sweeping back to neck.
    face.addQuadCurve(to: CGPoint(x: 588, y: 590), control: CGPoint(x: 645, y: 572))
    face.addLine(to: CGPoint(x: 580, y: 725))
    face.closeSubpath()
    fillAndStroke(ctx, face, fill: skin, stroke: ink, lineWidth: 15, join: .round)

    // Excited manga grin (open smiling mouth in profile).
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 730, y: 632))
    mouth.addQuadCurve(to: CGPoint(x: 662, y: 640), control: CGPoint(x: 695, y: 642))
    mouth.addQuadCurve(to: CGPoint(x: 712, y: 600), control: CGPoint(x: 668, y: 600))
    mouth.closeSubpath()
    fillAndStroke(ctx, mouth, fill: rgb(0xc93b2b), stroke: ink, lineWidth: 11)

    // Bright white upper teeth bar clipped inside mouth.
    ctx.saveGState()
    ctx.addPath(mouth)
    ctx.clip()
    ctx.setFillColor(rgb(0xffffff))
    ctx.fill(CGRect(x: 655, y: 624, width: 80, height: 22))
    ctx.setFillColor(rgb(0xf27d6b))
    ctx.fillEllipse(in: CGRect(x: 672, y: 592, width: 45, height: 24))
    ctx.restoreGState()
    // Re-stroke mouth outline cleanly on top.
    ctx.saveGState()
    ctx.addPath(mouth)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(11)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Expressive manga eye in side profile.
    let eyeWhite = CGMutablePath()
    eyeWhite.move(to: CGPoint(x: 652, y: 696))
    eyeWhite.addQuadCurve(to: CGPoint(x: 714, y: 688), control: CGPoint(x: 686, y: 698))
    eyeWhite.addLine(to: CGPoint(x: 706, y: 654))
    eyeWhite.addQuadCurve(to: CGPoint(x: 650, y: 664), control: CGPoint(x: 678, y: 652))
    eyeWhite.closeSubpath()
    fillAndStroke(ctx, eyeWhite, fill: rgb(0xffffff), stroke: ink, lineWidth: 9)

    // Tall vertical manga iris looking forward.
    let iris = CGPath(ellipseIn: CGRect(x: 680, y: 655, width: 28, height: 36), transform: nil)
    ctx.addPath(iris)
    ctx.setFillColor(ink)
    ctx.fillPath()

    // Crisp bright manga eye catchlights (big top glint + small bottom glint).
    ctx.setFillColor(rgb(0xffffff))
    ctx.fillEllipse(in: CGRect(x: 683, y: 675, width: 12, height: 12))
    ctx.fillEllipse(in: CGRect(x: 694, y: 661, width: 6, height: 6))

    // Thick winged upper eyelash for classic manga expression.
    let lash = CGMutablePath()
    lash.move(to: CGPoint(x: 646, y: 694))
    lash.addQuadCurve(to: CGPoint(x: 716, y: 688), control: CGPoint(x: 685, y: 702))
    ctx.saveGState()
    ctx.addPath(lash)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Bold angled eyebrow slanted down toward the nose for intense speed focus.
    let brow = CGMutablePath()
    brow.move(to: CGPoint(x: 640, y: 724))
    brow.addLine(to: CGPoint(x: 720, y: 704))
    ctx.saveGState()
    ctx.addPath(brow)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Manga cheek blush hashes.
    for dx in [CGFloat(0), 14] {
        let blush = CGMutablePath()
        blush.move(to: CGPoint(x: 648 + dx, y: 644))
        blush.addLine(to: CGPoint(x: 638 + dx, y: 628))
        ctx.saveGState()
        ctx.addPath(blush)
        ctx.setStrokeColor(hotOrange)
        ctx.setLineWidth(6)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Wild spiky manga hair swept violently backward by the wind!
    let hair = CGMutablePath()
    hair.move(to: CGPoint(x: 725, y: 710))
    // Front bang spike jutting out over forehead.
    hair.addQuadCurve(to: CGPoint(x: 778, y: 752), control: CGPoint(x: 758, y: 718))
    hair.addQuadCurve(to: CGPoint(x: 705, y: 765), control: CGPoint(x: 742, y: 760))
    // Top crown spike.
    hair.addQuadCurve(to: CGPoint(x: 748, y: 832), control: CGPoint(x: 735, y: 795))
    hair.addQuadCurve(to: CGPoint(x: 635, y: 825), control: CGPoint(x: 695, y: 835))
    // Long dramatic upper wind-swept spike.
    hair.addQuadCurve(to: CGPoint(x: 448, y: 868), control: CGPoint(x: 555, y: 865))
    hair.addQuadCurve(to: CGPoint(x: 545, y: 785), control: CGPoint(x: 495, y: 815))
    // Longest central manga hair spike shooting left!
    hair.addQuadCurve(to: CGPoint(x: 372, y: 792), control: CGPoint(x: 465, y: 800))
    hair.addQuadCurve(to: CGPoint(x: 515, y: 725), control: CGPoint(x: 445, y: 748))
    // Lower wind-swept spike.
    hair.addQuadCurve(to: CGPoint(x: 400, y: 705), control: CGPoint(x: 455, y: 720))
    hair.addQuadCurve(to: CGPoint(x: 538, y: 668), control: CGPoint(x: 470, y: 680))
    // Nape spike above collar.
    hair.addQuadCurve(to: CGPoint(x: 462, y: 635), control: CGPoint(x: 500, y: 655))
    hair.addQuadCurve(to: CGPoint(x: 575, y: 620), control: CGPoint(x: 520, y: 622))
    // Sideburn lock in front of ear up to temple.
    hair.addLine(to: CGPoint(x: 608, y: 682))
    hair.addLine(to: CGPoint(x: 645, y: 720))
    hair.addLine(to: CGPoint(x: 725, y: 710))
    hair.closeSubpath()

    ctx.saveGState()
    ctx.addPath(hair)
    ctx.setFillColor(ink)
    ctx.fillPath()
    ctx.restoreGState()

    // Warm espresso manga hair highlight zig-zag across the spikes.
    let hairSheen = poly([
        (675, 785), (535, 815), (585, 775), (495, 765), (610, 742), (650, 762),
    ])
    ctx.saveGState()
    ctx.addPath(hairSheen)
    ctx.setFillColor(rgb(0x4a2410))
    ctx.fillPath()
    ctx.restoreGState()

    // Anime ear drawn cleanly over the hairline at the side of the head.
    let ear = CGMutablePath()
    ear.move(to: CGPoint(x: 602, y: 672))
    ear.addQuadCurve(to: CGPoint(x: 558, y: 650), control: CGPoint(x: 568, y: 680))
    ear.addQuadCurve(to: CGPoint(x: 596, y: 622), control: CGPoint(x: 556, y: 620))
    fillAndStroke(ctx, ear, fill: skin, stroke: ink, lineWidth: 13)
}

func drawFrontArm(_ ctx: CGContext) {
    // Front arm bent sharply, pumping forward in sprint.
    let frontArm = CGMutablePath()
    frontArm.move(to: CGPoint(x: 575, y: 520))
    frontArm.addLine(to: CGPoint(x: 620, y: 415))
    frontArm.addLine(to: CGPoint(x: 745, y: 485))

    ctx.saveGState()
    ctx.addPath(frontArm)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(72)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Fill the inner sleeve by stroking with 42pt width, plus orange wrist cuff inside the same stroke mask.
    ctx.addPath(frontArm)
    ctx.setLineWidth(42)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    ctx.setFillColor(jacket)
    ctx.fill(CGRect(x: 520, y: 360, width: 280, height: 220))

    // Crisp orange cuff band clipped cleanly to the sleeve interior.
    let cuffPoly = poly([(685, 495), (722, 516), (755, 458), (718, 437)])
    ctx.addPath(cuffPoly)
    ctx.setFillColor(hotOrange)
    ctx.fillPath()
    ctx.addPath(cuffPoly)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(10)
    ctx.strokePath()
    ctx.restoreGState()

    // Front clenched fist punching forward.
    let fist = CGPath(ellipseIn: CGRect(x: 722, y: 455, width: 72, height: 68), transform: nil)
    fillAndStroke(ctx, fist, fill: skin, stroke: ink, lineWidth: 15)
}

func drawForegroundStreaks(_ ctx: CGContext) {
    // Sharp foreground speed streaks overlapping the edges for explosive forward motion.
    streak(ctx, xLeft: 95, xRight: 635, y: 874, thickness: 18, peakRatio: 0.2, color: rgb(0xfff9ed, 0.95))
    streak(ctx, xLeft: 105, xRight: 500, y: 138, thickness: 20, peakRatio: 0.2, color: rgb(0xfff9ed, 0.95))
    streak(ctx, xLeft: 735, xRight: 918, y: 340, thickness: 16, peakRatio: 0.3, color: rgb(0xfff9ed, 0.92))
    streak(ctx, xLeft: 785, xRight: 922, y: 585, thickness: 14, peakRatio: 0.3, color: rgb(0xffe599, 0.90))

    // Wind-cutter sonic arc in front of the runner's fist/knee.
    let shock = CGMutablePath()
    shock.move(to: CGPoint(x: 815, y: 565))
    shock.addQuadCurve(to: CGPoint(x: 825, y: 385), control: CGPoint(x: 870, y: 475))
    shock.addQuadCurve(to: CGPoint(x: 815, y: 565), control: CGPoint(x: 842, y: 475))
    shock.closeSubpath()
    ctx.addPath(shock)
    ctx.setFillColor(rgb(0xfff9ed, 0.94))
    ctx.fillPath()
}

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

    drawSpeedBackground(ctx)

    // Subtle drop shadow behind the character so he pops off the speed lines.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -10, height: -12), blur: 20, color: rgb(0x4a1200, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    drawLimbsBehind(ctx)
    drawZipperCapeTab(ctx)
    drawTorsoAndFrontLeg(ctx)
    drawHead(ctx)
    drawFrontArm(ctx)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    drawForegroundStreaks(ctx)
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
