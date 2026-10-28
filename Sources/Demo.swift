// Demo mode for README screenshots: sample history, no reading or writing of the real one.
// Built only by Scripts/screenshot.sh (swiftc -D DEMO).

#if DEMO
import AppKit

extension ClipStore {
    static var demoItems: [ClipItem] {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let dutch = Bundle.main.preferredLocalizations.first == "nl"
        let messages = dutch ? "Berichten" : "Messages", notes = dutch ? "Notities" : "Notes"
        func item(_ text: String, _ minutes: Double, _ bundleID: String, _ app: String) -> ClipItem {
            ClipItem(text: text, date: ago(minutes), appBundleID: bundleID, appName: app)
        }
        func file(_ name: String, _ minutes: Double) -> ClipItem {
            ClipItem(date: ago(minutes), appBundleID: "com.apple.finder", appName: "Finder",
                     filePaths: [NSHomeDirectory() + "/Documents/" + name])
        }
        func secret(_ text: String, _ minutes: Double) -> ClipItem {
            ClipItem(text: text, date: ago(minutes), appBundleID: "com.apple.Notes", appName: notes,
                     sensitiveUntil: now.addingTimeInterval(Secrets.lifetime))
        }
        if dutch {
            return [
                item("https://www.rijksmuseum.nl/nl/bezoeken", 0.2, "com.apple.Safari", "Safari"),
                item("Zullen we donderdag om 10:00 afspreken? Ik neem het prototype mee.", 3, "com.apple.MobileSMS", messages),
                secret("Zomer2026!", 4),
                file("Offerte Q4.pdf", 5),
                item("#FF6A00", 8, "com.apple.Notes", notes),
                item("const totaal = items.reduce((som, i) => som + i.prijs, 0);", 15, "com.apple.Terminal", "Terminal"),
                item("hallo@voorbeeld.nl", 26, "com.apple.mail", "Mail"),
                item("Kwartaalcijfers: omzet 12% hoger dan vorig jaar, vooral door de nieuwe abonnementen.", 42, "com.apple.Notes", notes),
                item("#34C759", 60, "com.apple.Notes", notes),
                item("Vergaderruimte 4.12 op de vierde verdieping, naast de koffieautomaat.", 95, "com.apple.MobileSMS", messages),
                item("https://github.com/SvenwifAI/control-c", 130, "com.apple.Safari", "Safari"),
                item("Tot morgen! Groetjes, Anne", 200, "com.apple.mail", "Mail"),
            ]
        }
        return [
            item("https://developer.apple.com/design/human-interface-guidelines/", 0.2, "com.apple.Safari", "Safari"),
            item("Let's meet Thursday at 10:00. I'll bring the prototype.", 3, "com.apple.MobileSMS", messages),
            secret("Summer2026!", 4),
            file("Proposal Q4.pdf", 5),
            item("#5E5CE6", 8, "com.apple.Notes", notes),
            item("let total = items.reduce(0) { $0 + $1.price }", 15, "com.apple.Terminal", "Terminal"),
            item("hello@example.com", 26, "com.apple.mail", "Mail"),
            item("Quarterly report: revenue up 12% year over year, driven by the new subscription plans.", 42, "com.apple.Notes", notes),
            item("#34C759", 60, "com.apple.Notes", notes),
            item("The meeting room is 4.12 on the fourth floor, next to the coffee machine.", 95, "com.apple.MobileSMS", messages),
            item("https://github.com/SvenwifAI/control-c", 130, "com.apple.Safari", "Safari"),
            item("func greet(_ name: String) -> String { \"Hello, \\(name)!\" }", 200, "com.apple.Terminal", "Terminal"),
        ]
    }
}

extension AppDelegate {
    /// Shows the picker centred over a plain backdrop and writes its frame for cropping.
    func showDemo() {
        guard let screen = NSScreen.main else { return }
        let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let view = NSView()
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = screen.frame
        gradient.colors = [NSColor(red: 0.55, green: 0.70, blue: 0.98, alpha: 1).cgColor,
                           NSColor(red: 0.78, green: 0.70, blue: 0.96, alpha: 1).cgColor,
                           NSColor(red: 0.98, green: 0.80, blue: 0.82, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        view.layer = gradient
        backdrop.contentView = view
        backdrop.orderFrontRegardless()
        demoBackdrop = backdrop

        model.expanded = ProcessInfo.processInfo.environment["DEMO_EXPANDED"] == "1"
        show()
        let f = panel.frame
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.midY - f.height / 2))
        let p = panel.frame
        let scale = screen.backingScaleFactor
        // Pixel crop rect (top-left origin) for sips: height width y x
        let crop = "\(Int(p.height * scale)) \(Int(p.width * scale)) \(Int((screen.frame.maxY - p.maxY) * scale)) \(Int(p.minX * scale))"
        try? crop.write(toFile: ProcessInfo.processInfo.environment["DEMO_CROP_FILE"] ?? "/dev/null",
                        atomically: true, encoding: .utf8)
    }
}

nonisolated(unsafe) private var backdropWindow: NSWindow?

extension AppDelegate {
    var demoBackdrop: NSWindow? {
        get { backdropWindow }
        set { backdropWindow = newValue }
    }
}
#endif
