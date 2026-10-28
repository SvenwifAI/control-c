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

    /// A shortcut from a key press, or nil when it would break normal use of the Mac: a bare key,
    /// ⌥ with a character key (that types ©, √ and the like), or a standard command such as ⌘V.
    init?(event: NSEvent) {
        self.init(keyCode: Int(event.keyCode),
                  modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift]),
                  characters: event.charactersIgnoringModifiers ?? "")
    }

    init?(keyCode code: Int, modifiers mods: NSEvent.ModifierFlags, characters: String) {
        let named: [Int: String] = [
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Space: "Space", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]
        guard code != kVK_Escape else { return nil }
        let typesCharacter = named[code] == nil || code == kVK_Space
        let strong = !mods.intersection([.command, .control]).isEmpty
        guard strong || (mods.contains(.option) && !typesCharacter) else { return nil }
        let label = named[code] ?? characters.uppercased()
        guard !label.isEmpty else { return nil }
        let reserved: [(NSEvent.ModifierFlags, Set<String>)] = [
            ([.command], ["V", "C", "X", "Z", "A", "Q", "W", "H", "M", "S", "⇥", "Space"]),
            ([.command, .shift], ["Z", "3", "4", "5"]),
            ([.control], ["C", "D", "Z", "A", "E", "K"]),
        ]
        guard !reserved.contains(where: { $0.0 == mods && $0.1.contains(label) }) else { return nil }
        self.init(keyCode: code, modifiers: mods.rawValue, keyLabel: label)
    }

    /// The stored shortcut if it still passes the rules above (the defaults file can be edited by hand).
    var validated: Shortcut {
        Shortcut(keyCode: keyCode, modifiers: flags, characters: keyLabel == "Space" ? " " : keyLabel) != nil ? self : .standard
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
    @Published var detectSecrets: Bool {
        didSet {
            defaults.set(detectSecrets, forKey: "detectSecrets")
            onDetectSecretsChange(detectSecrets)
        }
    }
    @Published var excludedApps: [String] {
        didSet {
            defaults.set(excludedApps, forKey: "excludedApps")
            onExcludedChange(excludedApps)
        }
    }
    @Published var hideWhenSharing: Bool {
        didSet {
            defaults.set(hideWhenSharing, forKey: "hideWhenSharing")
            onSharingChange(hideWhenSharing)
        }
    }
    /// False when the history can't be encrypted (no Keychain access) and lives in memory only.
    @Published var historyIsSaved = true
    /// True while the recorder listens, so the current global shortcut can be paused.
    @Published var isRecording = false { didSet { onRecordingChange(isRecording) } }
    @Published var shortcutTaken = false

    var onShortcutChange: () -> Void = {}
    var onLimitsChange: () -> Void = {}
    var onRecordingChange: (Bool) -> Void = { _ in }
    var onExcludedChange: ([String]) -> Void = { _ in }
    var onDetectSecretsChange: (Bool) -> Void = { _ in }
    var onSharingChange: (Bool) -> Void = { _ in }

    static let itemLimits = [20, 60, 100, 200]
    static let retentionChoices = [1, 7, 30]

    var maxAge: TimeInterval { TimeInterval(retentionDays) * 24 * 3600 }

    private init() {
        // Only values the Settings window can produce: the defaults file is editable by anyone.
        shortcut = (defaults.data(forKey: "shortcut")).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }?
            .validated ?? .standard
        let items = defaults.object(forKey: "maxItems") as? Int ?? 60
        maxItems = Self.itemLimits.contains(items) ? items : 60
        let days = defaults.object(forKey: "retentionDays") as? Int ?? 7
        retentionDays = Self.retentionChoices.contains(days) ? days : 7
        hideWhenSharing = defaults.object(forKey: "hideWhenSharing") as? Bool ?? true
        recognizeText = defaults.object(forKey: "recognizeText") as? Bool ?? true
        detectSecrets = defaults.object(forKey: "detectSecrets") as? Bool ?? true
        excludedApps = defaults.stringArray(forKey: "excludedApps") ?? []
    }
}

// MARK: - Window

final class SettingsWindowController {
    static let windowID = NSUserInterfaceItemIdentifier("ControlC.settings")
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
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
            w.identifier = Self.windowID
            w.center()
            window = w
            // A shortcut recorder left listening would turn the next key combination into the shortcut.
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { _ in
                    Settings.shared.isRecording = false
                })
            }
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
                Text("⌘↩ also sends messages in apps like Slack, Teams and Claude. If that clashes, try ⌘⇧V or ⌃⌥V.")
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                if !settings.historyIsSaved {
                    Label("History isn’t saved: no access to the Keychain. It is kept in memory until you quit.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Picker("Number of items", selection: $settings.maxItems) {
                    ForEach(Settings.itemLimits, id: \.self) { Text("\($0)").tag($0) }
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
                Toggle(isOn: $settings.hideWhenSharing) {
                    Text("Hide during screen sharing")
                    Text("The popup doesn’t show up in screen sharing, recordings or screenshots.")
                }
                Toggle("Start at login", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { setLogin(loginEnabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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
        .onChange(of: settings.isRecording) { if !settings.isRecording { removeMonitor() } }
    }

    private func toggleRecording() { settings.isRecording ? stop() : start() }

    private func start() {
        settings.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.identifier == SettingsWindowController.windowID else { return event }
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
        removeMonitor()
        settings.isRecording = false
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
