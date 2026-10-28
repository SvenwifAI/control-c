// Preferences: the global shortcut, history limits, excluded apps, and the window to change them.

import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt // NSEvent.ModifierFlags raw value
    var keyLabel: String

    static let standard = Shortcut(keyCode: kVK_Return, modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "↩")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    /// Symbols in Apple's order: ⌃⌥⇧⌘, then the key.
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + (keyLabel == "Space" ? L("Space") : keyLabel)
    }

    init(keyCode: Int, modifiers: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// A shortcut from a key press, or nil when it lacks ⌘, ⌥ or ⌃ (a bare key would swallow normal typing).
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        let code = Int(event.keyCode)
        let named: [Int: String] = [
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Space: "Space", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]
        guard code != kVK_Escape else { return nil }
        let label = named[code] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !label.isEmpty else { return nil }
        self.init(keyCode: code, modifiers: mods.rawValue, keyLabel: label)
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut")
            onShortcutChange()
        }
    }
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems"); onLimitsChange() } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays"); onLimitsChange() } }
    @Published var recognizeText: Bool { didSet { defaults.set(recognizeText, forKey: "recognizeText") } }
    @Published var detectSecrets: Bool { didSet { defaults.set(detectSecrets, forKey: "detectSecrets") } }
    @Published var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    /// True while the recorder listens, so the current global shortcut can be paused.
    @Published var isRecording = false { didSet { onRecordingChange(isRecording) } }
    @Published var shortcutTaken = false

    var onShortcutChange: () -> Void = {}
    var onLimitsChange: () -> Void = {}
    var onRecordingChange: (Bool) -> Void = { _ in }

    var maxAge: TimeInterval { TimeInterval(retentionDays) * 24 * 3600 }

    private init() {
        shortcut = (defaults.data(forKey: "shortcut")).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .standard
        maxItems = defaults.object(forKey: "maxItems") as? Int ?? 60
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 7
        recognizeText = defaults.object(forKey: "recognizeText") as? Bool ?? true
        detectSecrets = defaults.object(forKey: "detectSecrets") as? Bool ?? true
        excludedApps = defaults.stringArray(forKey: "excludedApps") ?? []
    }
}

// MARK: - Window

final class SettingsWindowController {
    private var window: NSWindow?
    let onClearHistory: () -> Void

    init(onClearHistory: @escaping () -> Void) { self.onClearHistory = onClearHistory }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Settings")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: .shared, onClearHistory: onClearHistory))
            w.center()
            window = w
        }
        // activate() is cooperative since macOS 14 and may be declined while another app is in use,
        // so bring the window forward regardless.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let onClearHistory: () -> Void
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                LabeledContent("Open clipboard") { ShortcutRecorder(settings: settings) }
                if settings.shortcutTaken {
                    Label("Another app already uses this shortcut.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("⌘↩ also sends messages in apps like Slack, Teams and Claude. If that clashes, try ⌥V or ⌘⇧V.")
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Picker("Number of items", selection: $settings.maxItems) {
                    ForEach([20, 60, 100, 200], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Keep for", selection: $settings.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                Toggle(isOn: $settings.recognizeText) {
                    Text("Recognize text in images")
                    Text("Search inside screenshots. Runs on your Mac; nothing goes online.")
                }
                Toggle(isOn: $settings.detectSecrets) {
                    Text("Recognize passwords and codes")
                    Text("2FA codes, API keys, card numbers and password-like text are never saved and disappear after 5 minutes.")
                }
                Button("Clear History…", role: .destructive, action: onClearHistory)
            }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("No apps excluded").foregroundStyle(.secondary)
                }
                ForEach(settings.excludedApps, id: \.self) { id in
                    ExcludedAppRow(bundleID: id) { settings.excludedApps.removeAll { $0 == id } }
                }
                Button("Add App…", action: addExcludedApp)
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Nothing you copy in these apps is ever stored. Useful for banking or a password file.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Start at login", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { setLogin(loginEnabled) }
                LabeledContent("Automatic pasting") {
                    if accessibilityGranted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = L("Exclude")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.excludedApps.contains(id) {
                settings.excludedApps.append(id)
            }
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Control+C login item: \(error)")
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 10) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
            Spacer()
            Button(action: onRemove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Stop excluding")
        }
    }
}

/// Click, then press the new key combination. Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var settings: Settings
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(settings.isRecording ? L("Press keys…") : settings.shortcut.display)
                    .font(.system(size: 13, weight: .medium, design: settings.isRecording ? .default : .rounded))
                    .foregroundStyle(settings.isRecording ? Color.accentColor : Color.primary)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if settings.shortcut != .standard && !settings.isRecording {
                Button { settings.shortcut = .standard } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help("Back to ⌘↩")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggleRecording() { settings.isRecording ? stop() : start() }

    private func start() {
        settings.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            if let s = Shortcut(event: event) {
                settings.shortcut = s
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.isRecording = false
    }
}
