// Draws Myna's app icon: a myna on a branch, talking into a speech bubble.
// Writes the Mac app icon set, the Android launcher icons, docs/icon.png and the site's icon and favicon.
// Run from the repo root: swift docs/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// `rounded`: the macOS squircle with margin and shadow. Otherwise full-bleed, for Android, which masks it itself.
func render(px: Int, rounded: Bool) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px)) // draw with y pointing down, like the design
    ctx.scaleBy(x: s, y: -s)

    let tile = rounded ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let body = rounded ? CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil) : CGPath(rect: tile, transform: nil)
    if rounded {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.35))
        ctx.addPath(body); ctx.setFillColor(color(0x1B1640)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let sky = CGGradient(colorsSpace: nil, colors: [color(0x4A3B9C), color(0x1B1640)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

    // Speech bubble with three dots: texts and calls.
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: CGRect(x: 560, y: 236, width: 270, height: 196), cornerWidth: 70, cornerHeight: 70)
    bubble.move(to: CGPoint(x: 600, y: 410)); bubble.addLine(to: CGPoint(x: 570, y: 486)); bubble.addLine(to: CGPoint(x: 660, y: 425))
    ctx.addPath(bubble); ctx.setFillColor(color(0xF6EBD2)); ctx.fillPath()
    for x in [638.0, 695, 752] {
        ctx.addEllipse(in: CGRect(x: x - 20, y: 314, width: 40, height: 40)); ctx.setFillColor(color(0x4A3B9C)); ctx.fillPath()
    }

    // Branch and feet.
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 170, y: 812)); ctx.addLine(to: CGPoint(x: 800, y: 812))
    ctx.setStrokeColor(color(0x9C6A3E)); ctx.setLineWidth(34); ctx.strokePath()
    for x in [430.0, 500] {
        ctx.move(to: CGPoint(x: x, y: 740)); ctx.addLine(to: CGPoint(x: x + 8, y: 800))
        ctx.setStrokeColor(color(0xF2B92B)); ctx.setLineWidth(20); ctx.strokePath()
    }

    // Tail, body and head: the myna's glossy near-black.
    let plumage = color(0x15111F)
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 300, y: 660)); tail.addLine(to: CGPoint(x: 168, y: 800)); tail.addLine(to: CGPoint(x: 236, y: 822)); tail.addLine(to: CGPoint(x: 360, y: 720))
    tail.closeSubpath()
    ctx.addPath(tail); ctx.setFillColor(plumage); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 250, y: 470, width: 400, height: 300)); ctx.setFillColor(plumage); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 400, y: 330, width: 230, height: 230)); ctx.setFillColor(plumage); ctx.fillPath()
    // Sheen on the back.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: 250, y: 470, width: 400, height: 300)); ctx.clip()
    let sheen = CGGradient(colorsSpace: nil, colors: [color(0x6E5BC9, 0.45), color(0x6E5BC9, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 380, y: 520), startRadius: 0, endCenter: CGPoint(x: 380, y: 520), endRadius: 220, options: [])
    ctx.restoreGState()
    // White wing patch.
    ctx.addEllipse(in: CGRect(x: 330, y: 610, width: 120, height: 54)); ctx.setFillColor(color(0xEDEAF6)); ctx.fillPath()

    // Yellow beak and the bare yellow skin around the eye.
    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 610, y: 418)); beak.addLine(to: CGPoint(x: 712, y: 452)); beak.addLine(to: CGPoint(x: 612, y: 482)); beak.closeSubpath()
    ctx.addPath(beak); ctx.setFillColor(color(0xF2B92B)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 520, y: 400, width: 70, height: 56)); ctx.setFillColor(color(0xF2B92B)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 543, y: 414, width: 28, height: 28)); ctx.setFillColor(color(0x0B0912)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 555, y: 419, width: 9, height: 9)); ctx.setFillColor(color(0xFFFFFF, 0.9)); ctx.fillPath()
    ctx.restoreGState()

    if rounded {
        ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 184.5, cornerHeight: 184.5, transform: nil))
        ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(1); ctx.strokePath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

// Mac
let mac = "mac/Sources/Assets.xcassets/AppIcon.appiconset"
for px in [16, 32, 64, 128, 256, 512, 1024] { try write(render(px: px, rounded: true), "\(mac)/icon_\(px).png") }
let entries = [(16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128), (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024)]
let images = entries.map { #"{"idiom":"mac","size":"\#($0.0)x\#($0.0)","scale":"\#($0.1)x","filename":"icon_\#($0.2).png"}"# }
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(toFile: "\(mac)/Contents.json", atomically: true, encoding: .utf8)
try #"{"info":{"author":"xcode","version":1}}"#.write(toFile: "mac/Sources/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)

// Android launcher icons (the launcher rounds them)
for (density, px) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try write(render(px: px, rounded: false), "android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}

// README, site icon and favicon
try write(render(px: 512, rounded: true), "docs/icon.png")
try write(render(px: 512, rounded: true), "docs/site/icon.png")
try write(render(px: 64, rounded: true), "docs/site/favicon.png")
print("Icons written")
