// Demo mode for README screenshots: sample history, no reading or writing of the real one.
// Built only by Scripts/screenshot.sh (swiftc -D DEMO).

#if DEMO
import AppKit

extension ClipStore {
    static var demoItems: [ClipItem] {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            ClipItem(text: "https://developer.apple.com/design/human-interface-guidelines/", date: ago(0.2),
                     appBundleID: "com.apple.Safari", appName: "Safari"),
            ClipItem(text: "Let's meet Thursday at 10:00. I'll bring the prototype.", date: ago(3),
                     appBundleID: "com.apple.MobileSMS", appName: "Messages"),
            ClipItem(text: "#5E5CE6", date: ago(8), appBundleID: "com.apple.Notes", appName: "Notes"),
            ClipItem(text: "let total = items.reduce(0) { $0 + $1.price }", date: ago(15),
                     appBundleID: "com.apple.Terminal", appName: "Terminal"),
            ClipItem(text: "hello@example.com", date: ago(26), appBundleID: "com.apple.mail", appName: "Mail"),
            ClipItem(text: "Quarterly report: revenue up 12% year over year, driven by the new subscription plans.",
                     date: ago(42), appBundleID: "com.apple.Notes", appName: "Notes"),
            ClipItem(text: "#34C759", date: ago(60), appBundleID: "com.apple.Notes", appName: "Notes"),
            ClipItem(text: "The meeting room is 4.12 on the fourth floor, next to the coffee machine.", date: ago(95),
                     appBundleID: "com.apple.MobileSMS", appName: "Messages"),
            ClipItem(text: "https://github.com/SvenwifAI/control-c", date: ago(130),
                     appBundleID: "com.apple.Safari", appName: "Safari"),
            ClipItem(text: "func greet(_ name: String) -> String { \"Hello, \\(name)!\" }", date: ago(200),
                     appBundleID: "com.apple.Terminal", appName: "Terminal"),
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
