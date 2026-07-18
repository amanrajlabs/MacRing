// Generates the MacRing app icon: a ring of orbs on a dark rounded square.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    // macOS icon grid: content square inset ~10%, continuous-ish corner radius.
    let inset = s * 0.09
    let square = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: square, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.16, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!
        .draw(in: bg, angle: -90)

    let center = CGPoint(x: s / 2, y: s / 2)
    let ringRadius = s * 0.26
    let orbRadius = s * 0.062
    let accent = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    for i in 0..<8 {
        let a = CGFloat(i) / 8 * 2 * .pi + .pi / 2
        let p = CGPoint(x: center.x + ringRadius * cos(a), y: center.y + ringRadius * sin(a))
        let orb = NSRect(x: p.x - orbRadius, y: p.y - orbRadius,
                         width: orbRadius * 2, height: orbRadius * 2)
        (i == 0 ? accent : NSColor.white.withAlphaComponent(0.88)).setFill()
        NSBezierPath(ovalIn: orb).fill()
    }
    let hub = s * 0.045
    accent.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub,
                                width: hub * 2, height: hub * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for v in variants {
    let rep = render(px: v.px)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: outDir.appendingPathComponent("\(v.name).png"))
}
print("Wrote \(variants.count) icons to \(outDir.path)")
