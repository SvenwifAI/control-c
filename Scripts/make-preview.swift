// Composes docs/preview.nl.png: the collapsed and expanded popup side by side, plus the main features.
// Run Scripts/screenshot.sh first, then: swift Scripts/make-preview.swift

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let docs = root.appendingPathComponent("docs")
guard let compact = NSImage(contentsOf: docs.appendingPathComponent("screenshot-compact.nl.png")),
      let expanded = NSImage(contentsOf: docs.appendingPathComponent("screenshot-expanded.nl.png")),
      let compactRep = compact.representations.first, let expandedRep = expanded.representations.first
else { fatalError("Run Scripts/screenshot.sh first") }

let W: CGFloat = 2600, H: CGFloat = 1960, pad: CGFloat = 140
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Top-left coordinates make the layout easier to read.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H - y - h, width: w, height: h) }

// Background: soft off-white with a faint lilac glow, like the screenshots' backdrop.
NSColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()
let glowCenter = NSPoint(x: W / 2, y: H - 150)
NSGradient(colors: [NSColor(red: 0.80, green: 0.78, blue: 1.0, alpha: 0.6), NSColor(red: 0.80, green: 0.78, blue: 1.0, alpha: 0)])!
    .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 1100, options: [])

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at r: NSRect, align: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = size * 0.18
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color, .paragraphStyle: style]).draw(in: r)
}

// Title
if let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")) {
    icon.draw(in: rect(W / 2 - 400, pad - 6, 132, 132))
}
text("Control+C", size: 100, weight: .bold, color: .black, at: rect(W / 2 - 250, pad + 2, 800, 130))
text("Je klembordgeschiedenis, één sneltoets weg.", size: 46, weight: .regular,
     color: NSColor(white: 0.35, alpha: 1), at: rect(0, pad + 170, W, 70), align: .center)

// Screenshots: equal height, side by side, each in a rounded frame with a soft shadow.
let shotH: CGFloat = 900, gap: CGFloat = 90, top: CGFloat = pad + 320
let cw = shotH * CGFloat(compactRep.pixelsWide) / CGFloat(compactRep.pixelsHigh)
let ew = shotH * CGFloat(expandedRep.pixelsWide) / CGFloat(expandedRep.pixelsHigh)
let startX = (W - cw - gap - ew) / 2

func framed(_ image: NSImage, _ r: NSRect) {
    let path = NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 50
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    image.draw(in: r)
    NSGraphicsContext.restoreGraphicsState()
}

framed(compact, rect(startX, top, cw, shotH))
framed(expanded, rect(startX + cw + gap, top, ew, shotH))

let labelColor = NSColor(white: 0.45, alpha: 1)
text("Ingeklapt", size: 34, weight: .semibold, color: labelColor, at: rect(startX, top + shotH + 34, cw, 50), align: .center)
text("Uitgeklapt  ·  Tab", size: 34, weight: .semibold, color: labelColor,
     at: rect(startX + cw + gap, top + shotH + 34, ew, 50), align: .center)

// Features: 3 × 2 grid of Settings-style glyphs with a title and one line.
let features: [(String, NSColor, String, String)] = [
    ("bolt.fill", .systemBlue, "Direct bij de hand", "Druk ⌘↩ en de popup staat meteen bij je muis."),
    ("text.viewfinder", .systemPurple, "Zoeken in screenshots", "Tekst in afbeeldingen wordt herkend, op je eigen Mac."),
    ("square.grid.2x2.fill", .systemOrange, "Kleur per type", "Tekst, links, bestanden, code en kleuren, met filters."),
    ("lock.fill", .systemGreen, "Privé", "Versleuteld, zonder extra rechten. Wachtwoorden worden nooit bewaard."),
    ("keyboard.fill", .systemPink, "Alles met het toetsenbord", "↩ kopieert, ⌘1–9 kiest direct, ⌘⌫ verwijdert, ⌘Z herstelt."),
    ("gearshape.fill", .systemGray, "Zoals jij het wilt", "Eigen sneltoets, bewaartermijn en uitgesloten apps."),
]
let gridTop = top + shotH + 150, colW = (W - pad * 2) / 3, rowH: CGFloat = 200
for (i, f) in features.enumerated() {
    let x = pad + CGFloat(i % 3) * colW + 30, y = gridTop + CGFloat(i / 3) * rowH
    let box = rect(x, y, 96, 96)
    let squircle = NSBezierPath(roundedRect: box, xRadius: 24, yRadius: 24)
    NSGradient(colors: [f.1.blended(withFraction: 0.18, of: .white)!, f.1])!.draw(in: squircle, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: f.0, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: box.midX - g.width / 2, y: box.midY - g.height / 2, width: g.width, height: g.height))
    }
    text(f.2, size: 38, weight: .semibold, color: .black, at: rect(x + 130, y + 2, colW - 170, 52))
    text(f.3, size: 30, weight: .regular, color: NSColor(white: 0.4, alpha: 1), at: rect(x + 130, y + 54, colW - 170, 90))
}

NSGraphicsContext.restoreGraphicsState()
let out = docs.appendingPathComponent("preview.nl.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
