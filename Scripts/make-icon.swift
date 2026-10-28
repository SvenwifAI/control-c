// Renders Resources/AppIcon.icns: a white clipboard glyph on a blue-to-indigo squircle,
// laid out on Apple's 1024 pt icon grid. Run: swift Scripts/make-icon.swift

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // Body: 824 pt squircle centred on the 1024 canvas, as macOS app icons are.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor.systemBlue.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1),
                        NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -90)
    // Soft top highlight, the glassy sheen of Tahoe icons.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: path, angle: -90)
    NSColor.white.withAlphaComponent(0.35).setStroke()
    path.lineWidth = 3 * s
    path.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: 430 * s, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(red: 0.33, green: 0.45, blue: 0.98, alpha: 1), .white]))
    if let glyph = NSImage(systemSymbolName: "list.clipboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: (CGFloat(px) - g.width) / 2, y: (CGFloat(px) - g.height) / 2 - 6 * s,
                              width: g.width, height: g.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
print("Wrote \(out.path)")
