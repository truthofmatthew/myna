// Draws the site's 1200×630 share image (og.jpg), in the same layout as Bower's.
// Run from the repo root after the screenshots: swift docs/make-og.swift <out.jpg>
import AppKit

let W = 1200.0, H = 630.0
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocusFlipped(true)

NSColor(srgbRed: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Right half: the icon's indigo sky with the Messages window on it.
let right = NSRect(x: 640, y: 0, width: 560, height: H)
NSGradient(colors: [NSColor(srgbRed: 0x6E / 255, green: 0x5B / 255, blue: 0xC9 / 255, alpha: 1),
                    NSColor(srgbRed: 0x1B / 255, green: 0x16 / 255, blue: 0x40 / 255, alpha: 1)])!.draw(in: right, angle: 300)
if let shot = NSImage(contentsOfFile: "docs/screenshots/messages.png") {
    let w = 760.0, h = w * shot.size.height / shot.size.width
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: right).addClip()
    shot.draw(in: NSRect(x: 700, y: (H - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1,
              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}

// Left half: icon, name, tagline.
NSImage(contentsOfFile: "docs/icon.png")?.draw(in: NSRect(x: 52, y: 128, width: 120, height: 120), from: .zero,
                                               operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
func text(_ s: String, _ font: NSFont, _ color: NSColor, _ y: Double) {
    (s as NSString).draw(at: NSPoint(x: 64, y: y), withAttributes: [.font: font, .foregroundColor: color])
}
let white = NSColor(srgbRed: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF2 / 255, alpha: 1)
text("MYNA", .systemFont(ofSize: 92, weight: .black), white, 262)
text("Your Android phone's texts, calls", .systemFont(ofSize: 31, weight: .regular), NSColor(white: 0.86, alpha: 1), 380)
text("and camera, on your Mac.", .systemFont(ofSize: 31, weight: .regular), NSColor(white: 0.86, alpha: 1), 420)
text("Free · Open source · macOS + Android", .systemFont(ofSize: 22, weight: .semibold),
     NSColor(srgbRed: 0x5F / 255, green: 0xCC / 255, blue: 0x33 / 255, alpha: 1), 476)

image.unlockFocus()
let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
rep.size = NSSize(width: W, height: H)
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Wrote \(CommandLine.arguments[1])")
