// Control+C — instant clipboard history. Press ⌘↩ anywhere.

import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ServiceManagement
import CryptoKit
import Vision
import UniformTypeIdentifiers
import ImageIO

/// UI text: English in the source, Dutch from nl.lproj when the Mac is set to Dutch.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }

// MARK: - Model

struct ClipItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String?
    var imageFile: String?
    var imageHash: String?
    var date = Date()
    var appBundleID: String?
    var appName: String?
    /// Text recognized in an image; "" once recognition ran and found nothing.
    var ocrText: String?
    /// Files copied in Finder (or elsewhere), kept as paths: the files themselves stay where they are.
    var filePaths: [String]?
    /// The formatted versions of copied text, so pasting keeps bold, links and colors.
    var rtf: Data?
    var html: Data?
    /// Set for recognized secrets: they live in memory until this moment and are never written to disk.
    /// Not part of the stored format, so a planted history file can't create one.
    var sensitiveUntil: Date?

    private enum CodingKeys: String, CodingKey {
        case id, text, imageFile, imageHash, date, appBundleID, appName, ocrText, filePaths, rtf, html
    }

    var isImage: Bool { imageFile != nil }
    var isFile: Bool { filePaths?.isEmpty == false }
    var isSensitive: Bool { sensitiveUntil != nil }
    var hasFormatting: Bool { rtf != nil || html != nil }
    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }

    /// The first file when its type is an image. Size and availability are checked off the main thread.
    var imageFileURL: URL? {
        guard let url = fileURLs.first, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        else { return nil }
        return url
    }

    /// Everything search looks at besides the app name.
    var searchText: String {
        if isSensitive { return "" } // a secret must not be findable by guessing its characters
        if isFile { return fileURLs.map(\.lastPathComponent).joined(separator: " ") + " " + (ocrText ?? "") }
        // Searching the first 64 KB keeps typing instant even with 1 MB items.
        return text.map { String($0.prefix(65_536)) } ?? "afbeelding image screenshot \(ocrText ?? "")"
    }

    var kind: ClipKind {
        if isSensitive { return .secret }
        if isFile { return .file }
        guard let text else { return .image }
        // Runs on every render, so the pattern checks only look at short texts.
        if text.utf8.count <= 2048 {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if swatch != nil { return .color }
            if !t.contains(where: \.isWhitespace) {
            if let scheme = URL(string: t)?.scheme?.lowercased(), scheme == "http" || scheme == "https" { return .link }
                if t.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/#) != nil { return .email }
            }
        }
        let head = text.prefix(4000)
        let markers = ["{", "}", ";", "=>", "func ", "def ", "const ", "import ", "</", "$ ", "()"]
        return markers.filter { head.contains($0) }.count >= 2 ? .code : .text
    }

    /// The color a copied hex value like "#FF6A00" describes.
    var swatch: Color? {
        guard let raw = text, raw.utf8.count <= 16, let m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .wholeMatch(of: #/\#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})/#) else { return nil }
        var hex = String(m.1)
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    var oneLine: String {
        if isSensitive { return "••••••••" } // always 8: the length of a secret is information too
        if isFile {
            let names = fileURLs.map(\.lastPathComponent)
            return names.count == 1 ? names[0] : names[0] + " " + L("+ %d more", names.count - 1)
        }
        guard let text else {
            guard let ocr = ocrText?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !ocr.isEmpty
            else { return L("Image") }
            return L("Image") + " · \(ocr.prefix(200))"
        }
        let collapsed = text.prefix(300).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? L("(whitespace)") : collapsed
    }

    /// True when the text spans several lines, which the one-line row would otherwise hide.
    var isMultiline: Bool { text?.prefix(10_000).contains(where: \.isNewline) == true }
}

/// What a clip is, each with its own SF Symbol and system color.
enum ClipKind: CaseIterable {
    case text, link, image, file, code, color, email, secret

    var label: String {
        switch self {
        case .text: L("Text")
        case .link: L("Links")
        case .image: L("Images")
        case .code: L("Code")
        case .color: L("Colors")
        case .email: L("Email")
        case .file: L("Files")
        case .secret: L("Secrets")
        }
    }

    var singular: String {
        switch self {
        case .text: L("Text")
        case .link: L("Link")
        case .image: L("Image")
        case .code: L("Code")
        case .color: L("Color")
        case .email: L("Email address")
        case .file: L("File")
        case .secret: L("Possible password")
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette.fill"
        case .email: "envelope.fill"
        case .file: "doc.fill"
        case .secret: "key.fill"
        }
    }

    var tint: Color {
        switch self {
        case .text: Color(nsColor: .systemGray)
        case .link: Color(nsColor: .systemBlue)
        case .image: Color(nsColor: .systemPurple)
        case .code: Color(nsColor: .systemOrange)
        case .color: Color(nsColor: .systemPink)
        case .email: Color(nsColor: .systemTeal)
        case .file: Color(nsColor: .systemIndigo)
        case .secret: Color(nsColor: .systemGray)
        }
    }
}

final class ClipStore: ObservableObject {
    static let maxTextBytes = 1_000_000
    static let maxImageBytes = 20_000_000
    /// Images above this many pixels are skipped: decoding one would stall the app and use gigabytes.
    static let maxImagePixels = 50_000_000
    /// Per format; the whole history is rewritten on save, so formatting must stay small.
    static let maxRichBytes = 500_000

    @Published private(set) var items: [ClipItem] = []
    /// False when the Keychain refused the key: the history then lives in memory only.
    @Published private(set) var isPersistent = true
    /// Bumped when a file thumbnail finishes loading, so rows redraw.
    @Published private(set) var thumbnailVersion = 0
    let dir: URL
    private var key: SymmetricKey?
    private var lastChange = -1
    private var timer: Timer?
    private var expiryTimer: Timer?
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbCache = NSCache<NSString, NSImage>()
    private var thumbsLoading: Set<String> = []
    private var fileSizes: [String: Int] = [:]
    private var iconCache: [String: NSImage] = [:]
    /// Image bytes that must not (or cannot) be on disk: memory-only mode, and images showing a secret.
    private var memoryImages: [String: Data] = [:]
    /// Image encoding, encryption and disk writes, in order and off the main thread.
    private let io = DispatchQueue(label: "ControlC.io", qos: .userInitiated)
    private let ocrQueue = DispatchQueue(label: "ControlC.ocr", qos: .utility)
    /// Apps that were frontmost since the previous poll, so a copy made just before switching apps
    /// is still traced back to an excluded app.
    private var recentApps: Set<String> = []
    private var activationObserver: NSObjectProtocol?
    private var saveScheduled = false
    private var nextSecretSweep = Date()

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    /// Pasteboard markers for content that clipboard tools must not keep.
    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
        "com.agilebits.onepassword",
        "net.antelle.keeweb",
    ]

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ControlC", isDirectory: true)
        #if DEMO
        items = Self.demoItems
        return
        #endif
        // Owner-only, and kept out of Time Machine: the history can contain anything you copied.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = dir
        try? excluded.setResourceValues(values)
        key = Vault.loadKey()
        isPersistent = key != nil
        load()
        expireOldItems()
        // Items stored by an older version that the current recognition sees as secrets.
        if Settings.shared.detectSecrets { purgeSecrets() }
    }

    private var historyURL: URL { dir.appendingPathComponent("history.enc") }
    /// Plain JSON from versions before encryption; merged in and removed whenever found.
    private var legacyHistoryURL: URL { dir.appendingPathComponent("history.json") }

    func start() {
        #if DEMO
        return
        #endif
        // Don't take what was already on the clipboard at launch: where it came from is unknown,
        // so it could be from an excluded app.
        lastChange = NSPasteboard.general.changeCount
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            if let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
                self?.recentApps.insert(id)
            }
        }
        items.filter { $0.isImage && $0.ocrText == nil }.forEach(recognizeText(in:))
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.expireOldItems()
        }
    }

    // MARK: Files

    /// Only files this app wrote itself ("<24 hex chars>.enc", or ".png" from before encryption);
    /// rejects anything else, such as a tampered history pointing at "../../somewhere".
    private func fileURL(_ name: String?) -> URL? {
        guard let name, name.count == 28, name.hasSuffix(".enc") || name.hasSuffix(".png"),
              name.dropLast(4).allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// Every file in the folder that belongs to this app.
    private func isOwnFile(_ name: String) -> Bool {
        fileURL(name) != nil || name == "history.enc" || name == "history.json"
            || (name.hasPrefix("history-unreadable-") && name.hasSuffix(".enc"))
    }

    /// The decrypted bytes of a stored image.
    private func imageData(_ name: String?) -> Data? {
        guard let name else { return nil }
        if let data = memoryImages[name] { return data }
        guard let url = fileURL(name), let raw = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension == "png" { return raw }
        guard let key else { return nil }
        return Vault.open(raw, with: key, context: name)
    }

    @discardableResult
    private static func writeFile(_ data: Data, to url: URL) -> Bool {
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    private static func writeSealed(_ data: Data, to url: URL, key: SymmetricKey?) -> Bool {
        guard let key, let sealed = Vault.seal(data, with: key, context: url.lastPathComponent) else { return false }
        return writeFile(sealed, to: url)
    }

    // MARK: Text recognition

    /// Reads the text in a copied image with Apple's on-device Vision, so screenshots become searchable.
    /// An image that shows a credential is treated like a copied secret: memory only, masked, short-lived.
    func recognizeText(in item: ClipItem) {
        guard Settings.shared.recognizeText else { return }
        let id = item.id
        let stored = item.imageFile != nil ? imageData(item.imageFile) : nil
        let fileURL = item.imageFileURL
        guard stored != nil || fileURL != nil else {
            if let name = item.imageFile { persistImage(name) }
            return
        }
        ocrQueue.async {
            let handler: VNImageRequestHandler
            if let stored {
                handler = VNImageRequestHandler(data: stored)
            } else if let fileURL, Self.isSafeImageFile(fileURL) {
                handler = VNImageRequestHandler(url: fileURL)
            } else { return } // a copied file: nothing of ours to write
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["nl-NL", "en-US"]
            try? handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let secret = Secrets.containsCredential(text)
            DispatchQueue.main.async { [weak self] in
                guard let self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[i].ocrText = text
                if secret, Settings.shared.detectSecrets {
                    self.makeSensitive(at: i)
                } else if let name = self.items[i].imageFile, self.memoryImages[name] != nil {
                    self.persistImage(name)
                }
                self.save()
            }
        }
    }

    /// Local, downloaded, and at most 20 MB and 50 MP: anything else could hang or exhaust memory.
    private static func isSafeImageFile(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .volumeIsLocalKey, .isUbiquitousItemKey,
                                         .ubiquitousItemDownloadingStatusKey]
        guard let v = try? url.resourceValues(forKeys: keys), let size = v.fileSize, size <= maxImageBytes,
              v.volumeIsLocal != false else { return false }
        if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus != .current { return false }
        return pixelCount(of: CGImageSourceCreateWithURL(url as CFURL, nil)).map { $0 <= maxImagePixels } ?? false
    }

    private static func pixelCount(of source: CGImageSource?) -> Int? {
        guard let source, let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return w * h
    }

    // MARK: Secrets

    /// Moves an item out of the stored history: memory only, masked, gone after a few minutes.
    private func makeSensitive(at i: Int) {
        items[i].sensitiveUntil = Date().addingTimeInterval(Secrets.lifetime)
        items[i].rtf = nil
        items[i].html = nil
        if let name = items[i].imageFile, let data = imageData(name) {
            memoryImages[name] = data
            if let url = fileURL(name), !items.contains(where: { $0.id != items[i].id && $0.imageFile == name }) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Removes recognized secrets whose few minutes are up.
    private func sweepSecrets() {
        nextSecretSweep = Date().addingTimeInterval(5)
        let now = Date()
        let expired = items.filter { ($0.sensitiveUntil ?? .distantFuture) < now }
        guard !expired.isEmpty else { return }
        items.removeAll { ($0.sensitiveUntil ?? .distantFuture) < now }
        expired.forEach(removeFile(of:))
        if let deleted = lastDeleted?.item, deleted.isSensitive, (deleted.sensitiveUntil ?? now) < now {
            lastDeleted = nil
            removeFile(of: deleted)
        }
    }

    /// Drops stored items that look like secrets, e.g. after turning recognition back on.
    func purgeSecrets() {
        let flagged = items.filter { item in
            !item.isSensitive && ((item.text.map(Secrets.looksSecret) ?? false)
                || (item.ocrText.map(Secrets.containsCredential) ?? false))
        }
        guard !flagged.isEmpty else { return }
        let ids = Set(flagged.map(\.id))
        items.removeAll { ids.contains($0.id) }
        flagged.forEach(removeFile(of:))
        save()
    }

    /// Drops everything that came from these apps, e.g. after excluding one.
    func purge(apps: [String]) {
        let removed = items.filter { $0.appBundleID.map(apps.contains) ?? false }
        guard !removed.isEmpty else { return }
        items.removeAll { $0.appBundleID.map(apps.contains) ?? false }
        removed.forEach(removeFile(of:))
        save()
    }

    // MARK: Capture

    private func poll() {
        if Date() >= nextSecretSweep { sweepSecrets() }
        let pb = NSPasteboard.general
        let frontmost = NSWorkspace.shared.frontmostApplication
        var involved = recentApps
        if let id = frontmost?.bundleIdentifier { involved.insert(id) }
        recentApps = frontmost?.bundleIdentifier.map { [$0] } ?? []

        let change = pb.changeCount
        guard change != lastChange else { return }
        lastChange = change
        guard let types = pb.types, !types.contains(where: { Self.ignoredTypes.contains($0.rawValue) }) else { return }

        // The writer can name itself; otherwise the frontmost app (or one just before) is the source.
        let source = pb.string(forType: Self.sourceType)
        if let source { involved.insert(source) }
        guard involved.isDisjoint(with: Settings.shared.excludedApps) else { return }
        let app = source.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first } ?? frontmost
        let appID = app?.bundleIdentifier ?? source, appName = app?.localizedName

        // Read everything first, then check nothing changed or got marked concealed meanwhile.
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let string = urls?.isEmpty == false ? nil : pb.string(forType: .string)
        let rtf = string == nil ? nil : pb.data(forType: .rtf)
        let html = string == nil ? nil : pb.data(forType: .html)
        let imageData = (urls?.isEmpty == false || string != nil) ? nil
            : (pb.data(forType: .png) ?? pb.data(forType: .tiff))
        guard pb.changeCount == change,
              !(pb.types ?? []).contains(where: { Self.ignoredTypes.contains($0.rawValue) }) else { return }

        if let urls, !urls.isEmpty {
            // Files first: Finder also puts their names on the pasteboard as plain text.
            let paths = urls.map(\.path)
            if let i = items.firstIndex(where: { $0.filePaths == paths }) { promote(at: i); return }
            let item = ClipItem(appBundleID: appID, appName: appName, filePaths: paths)
            insert(item)
            recognizeText(in: item)
        } else if let s = string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard s.utf8.count <= Self.maxTextBytes else { return }
            if Settings.shared.detectSecrets, Secrets.looksSecret(s) {
                // Kept in memory for a few minutes, masked, never saved; formatting is dropped.
                if let i = items.firstIndex(where: { $0.text == s }) {
                    makeSensitive(at: i)
                    promote(at: i)
                    save() // drops it from disk if it was stored before
                    return
                }
                var item = ClipItem(text: s, appBundleID: appID, appName: appName)
                item.sensitiveUntil = Date().addingTimeInterval(Secrets.lifetime)
                insert(item)
                return
            }
            let rich = rtf.flatMap { $0.count <= Self.maxRichBytes ? $0 : nil }
            let web = html.flatMap { $0.count <= Self.maxRichBytes ? $0 : nil }
            if let i = items.firstIndex(where: { $0.text == s }) {
                if rich != nil || web != nil { items[i].rtf = rich; items[i].html = web }
                promote(at: i)
                if i == 0 { save() }
                return
            }
            insert(ClipItem(text: s, appBundleID: appID, appName: appName, rtf: rich, html: web))
        } else if let raw = imageData {
            captureImage(raw, appID: appID, appName: appName)
        }
    }

    /// Checks size before decoding, converts to PNG and encrypts off the main thread, then adds the item.
    private func captureImage(_ raw: Data, appID: String?, appName: String?) {
        io.async { [weak self] in
            let source = CGImageSourceCreateWithData(raw as CFData, nil)
            guard let source, let pixels = Self.pixelCount(of: source), pixels <= Self.maxImagePixels else { return }
            var png = raw
            if (CGImageSourceGetType(source) as String?) != UTType.png.identifier {
                guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                let out = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(dest, cg, nil)
                guard CGImageDestinationFinalize(dest) else { return }
                png = out as Data
            }
            guard png.count <= Self.maxImageBytes else { return }
            let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            let name = "\(hash.prefix(24)).enc"
            DispatchQueue.main.async {
                guard let self else { return }
                // A copy of an image already in the list (secret or not) changes nothing on disk.
                if let i = self.items.firstIndex(where: { $0.imageHash == hash }) { self.promote(at: i); return }
                // Kept in memory until it's known not to show a secret; only then written to disk.
                self.memoryImages[name] = png
                let item = ClipItem(imageFile: name, imageHash: hash, appBundleID: appID, appName: appName)
                self.insert(item)
                if Settings.shared.recognizeText && Settings.shared.detectSecrets {
                    self.recognizeText(in: item) // writes the image afterwards if it holds no secret
                } else {
                    self.persistImage(name)
                    self.recognizeText(in: item)
                }
            }
        }
    }

    /// Writes an image that was held in memory, encrypted, once nothing argues against storing it.
    private func persistImage(_ name: String) {
        guard let key, let png = memoryImages[name],
              items.contains(where: { $0.imageFile == name && !$0.isSensitive }) else { return }
        let url = dir.appendingPathComponent(name)
        io.async { [weak self] in
            guard Self.writeSealed(png, to: url, key: key) else { return }
            DispatchQueue.main.async {
                guard let self, self.items.contains(where: { $0.imageFile == name && !$0.isSensitive }) else { return }
                self.memoryImages[name] = nil
                self.save() // the history can now refer to the file
            }
        }
    }

    // MARK: List changes

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        trimToLimit()
        save()
    }

    /// Keeps at most `maxItems` stored items; short-lived secrets don't count and are never evicted for space.
    private func trimToLimit() {
        let limit = Settings.shared.maxItems
        while items.lazy.filter({ !$0.isSensitive }).count > limit,
              let i = items.lastIndex(where: { !$0.isSensitive }) {
            removeFile(of: items.remove(at: i))
        }
    }

    /// Drops items not copied or used for `maxAge`, including their image files.
    func expireOldItems() {
        let cutoff = Date().addingTimeInterval(-Settings.shared.maxAge)
        let expired = items.filter { $0.date < cutoff }
        guard !expired.isEmpty else { return }
        items.removeAll { $0.date < cutoff }
        expired.forEach(removeFile(of:))
        save()
    }

    /// Re-applies the item limit and retention after they change in Settings.
    func applyLimits() {
        expireOldItems()
        trimToLimit()
        save()
    }

    private func promote(at i: Int) {
        guard i > 0 else {
            if !items.isEmpty { items[0].date = Date(); save() } // still counts as use
            return
        }
        var item = items.remove(at: i)
        item.date = Date()
        items.insert(item, at: 0)
        save()
    }

    /// Puts an item back on the system clipboard in one write; `plain` drops its formatting.
    func copyToPasteboard(_ item: ClipItem, promote shouldPromote: Bool = true, plain: Bool = false) {
        let pb = NSPasteboard.general
        if item.isSensitive {
            // Concealed, in the same write as the text, and kept off Universal Clipboard.
            pb.prepareForNewContents(with: .currentHostOnly)
        } else {
            pb.clearContents()
        }
        if item.isFile {
            pb.writeObjects(item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) } as [NSURL])
        } else if let t = item.text {
            let entry = NSPasteboardItem()
            entry.setString(t, forType: .string)
            if item.isSensitive { entry.setData(Data(), forType: Self.concealed) }
            if !plain, !item.isSensitive {
                if let rtf = item.rtf { entry.setData(rtf, forType: .rtf) }
                if let html = item.html { entry.setData(html, forType: .html) }
            }
            pb.writeObjects([entry])
        } else if let data = imageData(item.imageFile) {
            let entry = NSPasteboardItem()
            entry.setData(data, forType: .png)
            if item.isSensitive { entry.setData(Data(), forType: Self.concealed) }
            pb.writeObjects([entry])
        }
        lastChange = pb.changeCount
        if shouldPromote, let i = items.firstIndex(where: { $0.id == item.id }) { promote(at: i) }
    }

    /// Puts plain text on the clipboard as if the user copied it, e.g. text recognized in an image.
    func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: Delete

    /// The most recent deletion, kept (image file included) until it is undone or finalized.
    @Published private(set) var lastDeleted: (item: ClipItem, index: Int)?

    func delete(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        finalizeDelete()
        items.remove(at: i)
        lastDeleted = (item, i)
        save()
    }

    func undoDelete() {
        guard let (item, index) = lastDeleted else { return }
        lastDeleted = nil
        items.insert(item, at: min(index, items.count))
        save()
    }

    func finalizeDelete() {
        guard let (item, _) = lastDeleted else { return }
        lastDeleted = nil
        removeFile(of: item)
    }

    /// Removes every file of the history, also ones the app can't read right now, and replaces the
    /// key so copies of old files elsewhere (backups, snapshots) become unreadable.
    func clear() {
        lastDeleted = nil
        items.removeAll()
        memoryImages.removeAll()
        imageCache.removeAllObjects()
        saveScheduled = false
        io.sync {} // let pending writes finish before deleting
        #if DEMO
        return // the demo must never touch the real history
        #endif
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where isOwnFile(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
        if key != nil {
            key = Vault.rotateKey()
            isPersistent = key != nil
        }
        saveNow()
    }

    private func removeFile(of item: ClipItem) {
        guard let f = item.imageFile, !items.contains(where: { $0.imageFile == f }),
              lastDeleted?.item.imageFile != f else { return }
        memoryImages[f] = nil
        imageCache.removeObject(forKey: f as NSString)
        thumbCache.removeObject(forKey: f as NSString)
        if let url = fileURL(f) {
            io.async { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Images and icons

    /// A small thumbnail of a copied image, for rows. Returns nil until it has been made off the main thread.
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let f = item.imageFile else { return nil }
        if let cached = thumbCache.object(forKey: f as NSString) { return cached }
        loadImage(f, maxPixels: 96, into: thumbCache)
        return nil
    }

    /// The image scaled for the preview pane, made off the main thread like the thumbnails.
    func previewImage(for item: ClipItem) -> NSImage? {
        guard let f = item.imageFile else { return nil }
        if let cached = imageCache.object(forKey: f as NSString) { return cached }
        loadImage(f, maxPixels: 1600, into: imageCache)
        return nil
    }

    /// The original size in pixels, known once a thumbnail or preview has loaded.
    func imageSize(for item: ClipItem) -> CGSize? { item.imageFile.flatMap { imageSizes[$0] } }

    private var imagesLoading: Set<String> = []
    private var imageSizes: [String: CGSize] = [:]

    /// Decrypts and scales a stored image in the background, then redraws the rows that show it.
    private func loadImage(_ name: String, maxPixels: Int, into cache: NSCache<NSString, NSImage>) {
        let job = "\(maxPixels)|\(name)"
        guard !imagesLoading.contains(job) else { return }
        imagesLoading.insert(job)
        let inMemory = memoryImages[name], key = self.key, url = fileURL(name)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var data = inMemory
            if data == nil, let url, let raw = try? Data(contentsOf: url) {
                data = url.pathExtension == "png" ? raw : key.flatMap { Vault.open(raw, with: $0, context: name) }
            }
            var image: NSImage?
            var size: CGSize?
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil) {
                if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
                    size = CGSize(width: w, height: h)
                }
                if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, Self.thumbOptions(maxPixels)) {
                    image = NSImage(cgImage: cg, size: .zero)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.imagesLoading.remove(job)
                if let size { self.imageSizes[name] = size }
                if let image { cache.setObject(image, forKey: name as NSString) }
                self.thumbnailVersion += 1
            }
        }
    }

    private static func thumbOptions(_ size: Int) -> CFDictionary {
        [kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceThumbnailMaxPixelSize: size,
         kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
    }

    /// A thumbnail for a copied file (or its Finder icon), made off the main thread: the file may be
    /// big, on a network volume or still in iCloud. Returns nil until it is ready.
    func fileThumbnail(for item: ClipItem, size: Int = 96) -> NSImage? {
        guard let url = item.fileURLs.first else { return nil }
        let cacheKey = "\(size)|\(url.path)" as NSString
        if let cached = thumbCache.object(forKey: cacheKey) { return cached }
        guard !thumbsLoading.contains(cacheKey as String) else { return nil }
        thumbsLoading.insert(cacheKey as String)
        let isImage = item.imageFileURL != nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var thumb: NSImage?
            let byteSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if isImage, Self.isSafeImageFile(url), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, Self.thumbOptions(size)) {
                thumb = NSImage(cgImage: cg, size: .zero)
            } else if FileManager.default.fileExists(atPath: url.path) {
                thumb = NSWorkspace.shared.icon(forFile: url.path)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.thumbsLoading.remove(cacheKey as String)
                if let byteSize { self.fileSizes[url.path] = byteSize }
                if let thumb { self.thumbCache.setObject(thumb, forKey: cacheKey) }
                self.thumbnailVersion += 1
            }
        }
        return nil
    }

    /// The file's size once its thumbnail has loaded; nil until then or when it is gone.
    func fileSize(for item: ClipItem) -> Int? {
        item.fileURLs.first.flatMap { fileSizes[$0.path] }
    }

    func appIcon(for item: ClipItem) -> NSImage? {
        guard let id = item.appBundleID else { return nil }
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = icon
        return icon
    }

    // MARK: Load and save

    private func load() {
        guard let key else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: historyURL.path) {
            guard let sealed = try? Data(contentsOf: historyURL),
                  let data = Vault.open(sealed, with: key, context: historyURL.lastPathComponent),
                  let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else {
                // Wrong key or damaged file: set it aside instead of overwriting it, and start empty.
                // No cleanup either, since its images may still belong to it.
                let aside = dir.appendingPathComponent("history-unreadable-\(Int(Date().timeIntervalSince1970)).enc")
                if (try? fm.moveItem(at: historyURL, to: aside)) == nil {
                    self.key = nil // couldn't move it: write nothing rather than overwrite it
                    isPersistent = false
                }
                NSLog("Control+C: history could not be read and was set aside")
                return
            }
            items = decoded
        }
        if fm.fileExists(atPath: legacyHistoryURL.path) { mergeLegacyHistory() }
        upgradeStoredImages()
        guard saveNow() else { return } // keep every old file until the new history is safely written
        if fm.fileExists(atPath: legacyHistoryURL.path) { try? fm.removeItem(at: legacyHistoryURL) }
        removeOrphanedFiles()
    }

    /// Takes over a plain-text history from before encryption, leaving out anything that looks secret.
    private func mergeLegacyHistory() {
        guard let data = try? Data(contentsOf: legacyHistoryURL),
              let old = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        let known = Set(items.map(\.id))
        let added = old.filter { item in
            !known.contains(item.id) && !(item.text.map(Secrets.looksSecret) ?? false)
        }
        items = (items + added).sorted { $0.date > $1.date }
        trimToLimit()
    }

    /// Re-encrypts images still stored as plain PNG or in the first encrypted format.
    private func upgradeStoredImages() {
        guard let key else { return }
        for i in items.indices {
            guard let name = items[i].imageFile, let url = fileURL(name),
                  let raw = try? Data(contentsOf: url) else { continue }
            if url.pathExtension == "png" {
                let encName = String(name.dropLast(4)) + ".enc"
                if Self.writeSealed(raw, to: dir.appendingPathComponent(encName), key: key) {
                    items[i].imageFile = encName // the .png goes once the history is saved
                }
            } else if !Vault.isCurrentFormat(raw), let plain = Vault.open(raw, with: key, context: name) {
                _ = Self.writeSealed(plain, to: url, key: key)
            }
        }
    }

    /// Deletes image files no item refers to: leftovers of a crash, a quit right after deleting, or a
    /// plain PNG that was just re-encrypted.
    private func removeOrphanedFiles() {
        let used = Set(items.compactMap(\.imageFile))
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        // Images may belong to a history that was set aside; keep everything while one exists.
        guard !files.contains(where: { $0.lastPathComponent.hasPrefix("history-unreadable-") }) else { return }
        for url in files where fileURL(url.lastPathComponent) != nil && !used.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    /// Saves shortly after the last change, encrypted and off the main thread. Secrets are never included.
    private func save() {
        #if DEMO
        return
        #endif
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.saveScheduled else { return }
            self.saveScheduled = false
            let snapshot = self.storedItems, key = self.key, url = self.historyURL
            self.io.async { _ = Self.writeHistory(snapshot, key: key, to: url) }
        }
    }

    /// Saves right away and waits for it, e.g. before quitting or before deleting old files.
    @discardableResult
    func saveNow() -> Bool {
        #if DEMO
        return true
        #endif
        saveScheduled = false
        let snapshot = storedItems, key = self.key, url = historyURL
        return io.sync { Self.writeHistory(snapshot, key: key, to: url) }
    }

    /// What goes into the history file: no secrets, and no images that are only in memory (yet).
    private var storedItems: [ClipItem] {
        items.filter { !$0.isSensitive && ($0.imageFile.map { memoryImages[$0] == nil } ?? true) }
    }

    private static func writeHistory(_ items: [ClipItem], key: SymmetricKey?, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(items) else { return false }
        return writeSealed(data, to: url, key: key)
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Picker state

final class PickerModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    /// Row of the highlighted item; follows that item when the list changes underneath it.
    @Published var selection = 0 { didSet { selectedID = selected?.id } }
    private var selectedID: UUID?
    private var itemsObserver: AnyCancellable?
    @Published var focusToken = 0
    @Published var copiedID: UUID?
    @Published var expanded = UserDefaults.standard.bool(forKey: "expanded") {
        didSet {
            #if !DEMO // the demo shares the real app's settings
            UserDefaults.standard.set(expanded, forKey: "expanded")
            #endif
            onResize()
        }
    }
    let store: ClipStore
    /// Puts the item on the clipboard and closes the popup; `plain` drops formatting.
    var onChoose: (ClipItem, Bool) -> Void = { _, _ in }
    var onResize: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    init(store: ClipStore) {
        self.store = store
        // A new copy or an expiring secret above the highlight must not shift what ↩ copies.
        itemsObserver = store.$items.receive(on: RunLoop.main).sink { [weak self] _ in self?.reanchor() }
    }

    private func reanchor() {
        guard let id = selectedID, let i = filtered.firstIndex(where: { $0.id == id }) else {
            clampSelection()
            return
        }
        if i != selection { selection = i }
    }

    @Published var kindFilter: ClipKind? { didSet { selection = 0 } }

    var availableKinds: [ClipKind] {
        let present = Set(store.items.map(\.kind))
        return ClipKind.allCases.filter(present.contains)
    }

    /// ⌘← / ⌘→ steps through "Alles" and the kinds present.
    func stepKindFilter(_ delta: Int) {
        let scopes: [ClipKind?] = [nil] + availableKinds
        let i = scopes.firstIndex(of: kindFilter) ?? 0
        kindFilter = scopes[(i + delta + scopes.count) % scopes.count]
    }

    var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let items = kindFilter.map { kind in store.items.filter { $0.kind == kind } } ?? store.items
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.searchText.localizedCaseInsensitiveContains(q)
                || ($0.appName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var selected: ClipItem? {
        let f = filtered
        return f.indices.contains(selection) ? f[selection] : nil
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = max(0, min(count - 1, selection + delta))
    }

    func clampSelection() {
        selection = max(0, min(filtered.count - 1, selection))
    }

    @Published var confirmingClear = false

    /// Deletes with a short undo window; the image file is only removed once that window closes.
    func delete(_ item: ClipItem) {
        confirmingClear = false
        store.delete(item)
        clampSelection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.store.lastDeleted?.item.id == item.id { self?.store.finalizeDelete() }
        }
    }

    func undoDelete() {
        guard let item = store.lastDeleted?.item else { return }
        store.undoDelete()
        if let i = filtered.firstIndex(where: { $0.id == item.id }) { selection = i }
    }

    func clearAll() {
        store.clear()
        confirmingClear = false
        selection = 0
    }
}

// MARK: - Views

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

func relativeTime(_ date: Date) -> String {
    let s = Int(-date.timeIntervalSinceNow)
    switch s {
    case ..<60: return L("just now")
    case ..<3600: return L("%d min ago", s / 60)
    case ..<86400: return L("%d hr ago", s / 3600)
    case ..<172_800: return L("yesterday")
    default: return L("%d days ago", s / 86400)
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    @ObservedObject var store: ClipStore
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: UUID?
    /// Whether the list has more below its visible part; drives the bottom fade.
    @State private var moreBelow = false

    static let cardRadius: CGFloat = 24
    /// Transparent margin around the glass so its shadow and edge highlights aren't clipped.
    static let margin: CGFloat = 28
    static let searchHeight: CGFloat = 44

    var body: some View {
        // Liquid Glass (macOS 26): search capsule, round expand button and results card float
        // as separate glass shapes that blend where they meet.
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    searchField
                    expandButton
                }
                card
            }
        }
        // Lifts the glass off light backgrounds, where its edge alone disappears.
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .padding(Self.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: model.expanded ? 18 : 16))
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.searchHeight)
        .windowDraggable()
        .glassSurface(Capsule())
    }

    private var expandButton: some View {
        Button { model.expanded.toggle() } label: {
            Image(systemName: model.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.searchHeight, height: Self.searchHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .help(model.expanded ? L("Smaller (Tab)") : L("Larger with preview (Tab)"))
    }

    /// Small and quiet, at the far right of the filter row.
    private var settingsButton: some View {
        Button { model.onOpenSettings() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
    }

    private var card: some View {
        let items = model.filtered
        return VStack(spacing: 0) {
            kindBar
            if items.isEmpty {
                emptyState
            } else if model.expanded {
                HStack(spacing: 0) {
                    list(items).frame(width: 320)
                    Divider().opacity(0.4).padding(.vertical, 8)
                    PreviewPane(item: model.selected, store: store)
                }
            } else {
                list(items)
            }
            if model.expanded { footer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { banner.padding(.bottom, model.expanded ? 40 : 8) }
        .animation(.easeOut(duration: 0.15), value: store.lastDeleted?.item.id)
        .animation(.easeOut(duration: 0.15), value: model.confirmingClear)
        .windowDraggable()
        .glassSurface(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
    }

    /// Scope bar: "Alles" plus one capsule per kind present. Glyph-only when compact.
    private var kindBar: some View {
        HStack(spacing: 4) {
            scopeButton(nil)
            ForEach(model.availableKinds, id: \.self) { scopeButton($0) }
            Spacer(minLength: 0)
            settingsButton
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func scopeButton(_ kind: ClipKind?) -> some View {
        let active = model.kindFilter == kind
        let tint = kind?.tint ?? Color.primary
        return Button { model.kindFilter = kind } label: {
            HStack(spacing: 4) {
                if let kind { Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold)) }
                if kind == nil || model.expanded { Text(kind?.label ?? L("All")) }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(active ? (kind == nil ? Color.primary : Color.white) : (kind == nil ? Color.secondary : tint))
            .padding(.horizontal, kind == nil || model.expanded ? 9 : 7)
            .frame(height: 22)
            .background(
                Capsule().fill(active ? (kind == nil ? Color.primary.opacity(0.12) : tint) : Color.primary.opacity(0.05))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(kind?.label ?? L("All"))
    }

    private func list(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: model.expanded ? 2 : 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        let hovered = hoveredID == item.id
                        ClipRow(item: item, index: idx, selected: idx == model.selection,
                                compact: !model.expanded, copied: model.copiedID == item.id,
                                hovered: hovered, store: store)
                            .id(item.id)
                            .contentShape(Rectangle())
                            // Double click copies and closes; a single click copies and keeps the popup open.
                            // Not promoted on copy, so the row stays put under the second click.
                            .onTapGesture(count: 2) { model.onChoose(item, false) }
                            .simultaneousGesture(TapGesture().onEnded { copy(item, at: idx) })
                            // Outside the tap gestures above, so clicking × never also copies.
                            .overlay(alignment: .trailing) {
                                if hovered && model.copiedID != item.id {
                                    deleteButton(item, onAccent: idx == model.selection)
                                }
                            }
                            .onHover { inside in
                                if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
                            }
                            .contextMenu {
                                if item.hasFormatting {
                                    Button("Copy Without Formatting") { model.onChoose(item, true) }
                                }
                                Button("Copy") { copy(item, at: idx) }
                                if item.isFile {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
                                }
                                if !item.isSensitive, let ocr = item.ocrText, !ocr.isEmpty {
                                    Button("Copy Text from Image") { store.copyText(ocr) }
                                }
                                Divider()
                                Button("Delete") { model.delete(item) }
                                Button("Clear All…") { model.confirmingClear = true }
                            }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollIndicators(model.expanded ? .automatic : .never)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height < geo.contentSize.height - 2
            } action: { _, more in
                withAnimation(.easeOut(duration: 0.15)) { moreBelow = more }
            }
            .mask(edgeFade)
            .onChange(of: model.selection) {
                guard items.indices.contains(model.selection) else { return }
                proxy.scrollTo(items[model.selection].id)
            }
            .onChange(of: model.focusToken) {
                if let first = items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    /// A faint fade along the bottom edge, only while there is more to scroll to.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(height: moreBelow ? 22 : 0)
        }
    }

    private func copy(_ item: ClipItem, at idx: Int) {
        model.selection = idx
        store.copyToPasteboard(item, promote: false)
        model.copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if model.copiedID == item.id { model.copiedID = nil }
        }
    }

    private func deleteButton(_ item: ClipItem, onAccent: Bool) -> some View {
        Button { model.delete(item) } label: {
            Image(systemName: "xmark")
                .font(.system(size: model.expanded ? 9.5 : 8.5, weight: .bold))
                .foregroundStyle(onAccent ? Color.white : Color.secondary)
                .frame(width: model.expanded ? 20 : 16, height: model.expanded ? 20 : 16)
                .background(Circle().fill(onAccent ? Color.white.opacity(0.22) : Color.primary.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Delete (⌘⌫)")
        .padding(.trailing, 8)
    }

    @ViewBuilder private var banner: some View {
        if model.confirmingClear {
            BannerBar {
                Text(L("Clear all %d items?", store.items.count))
                Spacer(minLength: 8)
                Button("Cancel") { model.confirmingClear = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Clear All") { model.clearAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            }
        } else if store.lastDeleted != nil {
            BannerBar {
                Image(systemName: "trash").foregroundStyle(.secondary)
                Text("Deleted")
                Spacer(minLength: 8)
                Button { model.undoDelete() } label: {
                    HStack(spacing: 4) {
                        Text("Undo")
                        Text("⌘Z").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? L("Nothing copied yet") : L("No results"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(L("%d items", store.items.count))
                .foregroundStyle(.tertiary)
            Spacer()
            KeyHint(keys: "↩", label: L("Copy"))
            KeyHint(keys: "⌥↩", label: L("Without formatting"))
            KeyHint(keys: "⌘⌫", label: L("Delete"))
            KeyHint(keys: "esc", label: L("Close"))
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

extension View {
    /// Lets empty space behind this view move the panel; controls on top keep their own clicks.
    func windowDraggable() -> some View {
        background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }

    /// Liquid Glass with a light backing so text stays readable over busy windows.
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.5)))
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}

struct BannerBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
        .foregroundStyle(.secondary)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let compact: Bool
    let copied: Bool
    let hovered: Bool
    let store: ClipStore

    private var iconSize: CGFloat { compact ? 20 : 28 }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(item.oneLine)
                    .font(.system(size: 13, weight: compact ? .regular : .medium))
                    .lineLimit(1)
                if !compact {
                    Text([item.kind.singular, item.appName, relativeTime(item.date)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if item.isMultiline && !item.isSensitive && !copied && !hovered {
                Image(systemName: "text.append")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    .help(L("Several lines"))
            }
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            } else if hovered {
                Color.clear.frame(width: 20, height: 1) // room for the × the list overlays here
            } else if index < 9 {
                // Styled like a native menu key equivalent.
                Text("⌘\(index + 1)")
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: compact ? 28 : 44)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }

    /// The kind icon or thumbnail, with the source app's icon tucked into its corner like Spotlight does.
    private var thumbnail: some View {
        baseThumbnail.overlay(alignment: .bottomTrailing) {
            if let icon = store.appIcon(for: item) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: compact ? 11 : 15, height: compact ? 11 : 15)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(x: compact ? 3 : 4, y: compact ? 3 : 4)
            }
        }
    }

    @ViewBuilder private var baseThumbnail: some View {
        if item.isSensitive {
            KindIcon(kind: .secret, size: iconSize, selected: selected) // never a thumbnail of a secret
        } else if item.isFile, let thumb = store.fileThumbnail(for: item) {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
        } else if let img = store.thumbnail(for: item) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
                .overlay(iconBorder)
        } else if let swatch = item.swatch {
            RoundedRectangle(cornerRadius: compact ? 4.5 : 7, style: .continuous)
                .fill(swatch)
                .frame(width: iconSize, height: iconSize)
                .overlay(iconBorder)
        } else {
            KindIcon(kind: item.kind, size: iconSize, selected: selected)
        }
    }

    private var iconBorder: some View {
        RoundedRectangle(cornerRadius: compact ? 4.5 : 7, style: .continuous)
            .strokeBorder(selected ? Color.white.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: 0.5)
    }
}

/// A Settings-style glyph: white SF Symbol on a rounded square in the kind's system color.
struct KindIcon: View {
    let kind: ClipKind
    let size: CGFloat
    var selected = false

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(kind.tint.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.6 : 0), lineWidth: 0.5)
            )
    }
}

struct PreviewPane: View {
    let item: ClipItem?
    let store: ClipStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let item {
                Divider().opacity(0.6)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        KindIcon(kind: item.kind, size: 16)
                        Text(item.kind.singular)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.kind.tint)
                    }
                    .padding(.bottom, 3)
                    meta(L("Source"), item.appName ?? L("Unknown"))
                    meta(L("Copied"), item.date.formatted(date: .abbreviated, time: .shortened))
                    if item.isFile {
                        let urls = item.fileURLs
                        if urls.count > 1 { meta(L("Content"), L("%d files", urls.count)) }
                        meta(L("Location"), (urls[0].deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        if let size = store.fileSize(for: item) {
                            meta(L("Size"), ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        }
                    } else if item.isSensitive, let until = item.sensitiveUntil {
                        meta(L("Stored"), L("Not on disk · gone at %@", until.formatted(date: .omitted, time: .shortened)))
                    } else if let t = item.text {
                        if item.hasFormatting { meta(L("Formatting"), L("Kept · ⌥↩ copies without")) }
                        let lines = t.split(separator: "\n", omittingEmptySubsequences: false).count
                        meta(L("Content"), lines == 1 ? L("%d characters · 1 line", t.count) : L("%d characters · %d lines", t.count, lines))
                    } else if item.isImage {
                        if let size = store.imageSize(for: item) {
                            meta(L("Size"), "\(Int(size.width)) × \(Int(size.height))")
                        }
                        if let ocr = item.ocrText, !ocr.isEmpty {
                            let words = ocr.split(whereSeparator: \.isWhitespace).count
                            meta(L("Text"), L("%d words recognized · right-click to copy", words))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let item, item.isSensitive {
            VStack(spacing: 12) {
                KindIcon(kind: .secret, size: 56)
                Text(item.oneLine)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Hidden and never saved to disk. It disappears from the list after 5 minutes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .padding(20)
        } else if let item, item.isFile {
            VStack(spacing: 10) {
                if item.imageFileURL != nil, let img = store.fileThumbnail(for: item, size: 1200) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                } else if let icon = store.fileThumbnail(for: item) {
                    Image(nsImage: icon).resizable().frame(width: 128, height: 128)
                }
                Text(item.oneLine)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        } else if let item, let img = store.previewImage(for: item) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(20)
        } else if let item, let swatch = item.swatch {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(swatch)
                    .frame(width: 140, height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                Text(item.oneLine.uppercased())
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
            }
        } else if let item, let rich = Self.formatted(item) {
            ScrollView {
                Text(rich)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            // Links in copied text are shown, not followed: their target can differ from their label.
            .environment(\.openURL, OpenURLAction { _ in .discarded })
        } else if let item, let text = item.text {
            ScrollView {
                Text(String(text.prefix(8000)))
                    .font(.system(size: 13, design: item.kind == .code ? .monospaced : .default))
                    .foregroundStyle(item.kind == .link ? item.kind.tint : Color.primary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        } else {
            Color.clear
        }
    }

    private final class Rendered { let value: AttributedString?; init(_ v: AttributedString?) { value = v } }
    private static let renderedCache = NSCache<NSString, Rendered>()

    /// The RTF rendered as it will paste, parsed once per item; skipped for very large documents.
    private static func formatted(_ item: ClipItem) -> AttributedString? {
        guard let rtf = item.rtf, rtf.count < 200_000 else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = renderedCache.object(forKey: key) { return cached.value }
        let value = NSAttributedString(rtf: rtf, documentAttributes: nil)
            .flatMap { try? AttributedString($0, including: \.appKit) }
        renderedCache.setObject(Rendered(value), forKey: key)
        return value
    }

    private func meta(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.tertiary).frame(width: 82, alignment: .leading)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 11.5))
    }
}

// MARK: - Window & hotkey

final class ClipPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the glass draws its own
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // While an input method is composing (Japanese, Chinese, dead keys), keys belong to it.
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Replaces the current shortcut; false when another app already owns this combination.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // 'CLIP'
        return RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    lazy var store = ClipStore() // created after the single-instance check
    lazy var model = PickerModel(store: store)
    let settings = Settings.shared
    lazy var settingsWindow = SettingsWindowController { [weak self] in self?.clearHistory() }
    let openItem = NSMenuItem(title: L("Open Clipboard"), action: #selector(openFromMenu), keyEquivalent: "")
    var panel: ClipPanel!
    var hotKey: HotKey?
    var statusItem: NSStatusItem!
    let loginItem = NSMenuItem(title: L("Start at Login"), action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DEMO
        // Two copies would overwrite each other's history and delete each other's images.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0 != me }) {
            isDuplicate = true
            NSApp.terminate(nil)
            return
        }
        #endif
        store.start()

        panel = ClipPanel(size: CGSize(width: 340, height: 300))
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PickerView(model: model, store: store))
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        #if !DEMO
        panel.sharingType = settings.hideWhenSharing ? .none : .readOnly
        #endif
        model.onChoose = { [weak self] item, plain in self?.choose(item, plain: plain) }
        model.onResize = { [weak self] in self?.layoutPanel() }
        model.onOpenSettings = { [weak self] in self?.openSettings() }

        hotKey = HotKey { [weak self] in self?.toggle() }
        registerShortcut()
        settings.onShortcutChange = { [weak self] in
            if self?.settings.isRecording == false { self?.registerShortcut() }
        }
        settings.onRecordingChange = { [weak self] recording in
            if recording { self?.hotKey?.unregister() } else { self?.registerShortcut() }
        }
        settings.onLimitsChange = { [weak self] in self?.store.applyLimits() }
        settings.onExcludedChange = { [weak self] apps in self?.store.purge(apps: apps) }
        settings.onDetectSecretsChange = { [weak self] on in if on { self?.store.purgeSecrets() } }
        settings.onSharingChange = { [weak self] hide in self?.panel.sharingType = hide ? .none : .readOnly }
        settings.historyIsSaved = store.isPersistent
        storageObserver = store.$isPersistent.sink { [weak self] saved in self?.settings.historyIsSaved = saved }
        setupStatusItem()

        #if DEMO
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showDemo() }
        #endif
    }

    private var storageObserver: AnyCancellable?

    /// Set when another copy was already running: this one quits without ever opening the history.
    private var isDuplicate = false

    func applicationWillTerminate(_ notification: Notification) {
        guard !isDuplicate else { return }
        store.finalizeDelete()
        store.saveNow()
    }

    func registerShortcut() {
        settings.shortcutTaken = !(hotKey?.register(settings.shortcut) ?? true)
    }

    @objc func openSettings() {
        hide()
        settingsWindow.show()
    }

    // MARK: Panel

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        model.query = ""
        model.kindFilter = nil
        model.selection = 0
        anchor = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        userMoved = false
        layoutPanel()
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
    }

    /// What the panel hangs off: the mouse pointer, in Cocoa screen coordinates.
    private var anchor = NSRect.zero
    /// Set once the user drags the panel; resizing then keeps its top-left corner where they put it.
    private var userMoved = false
    private var isLayingOut = false

    func windowDidMove(_ notification: Notification) {
        if !isLayingOut { userMoved = true }
    }

    private var panelSize: CGSize {
        let m = PickerView.margin * 2
        let top = PickerView.searchHeight + 8
        if model.expanded { return CGSize(width: 740 + m, height: top + 420 + m) }
        // Seven rows, plus half of the eighth when there is more: a visual hint that the list scrolls.
        let count = store.items.count
        let rows = CGFloat(min(max(count, 3), 7)) + (count > 7 ? 0.5 : 0)
        return CGSize(width: 360 + m, height: top + 36 + rows * 28 + 8 + m)
    }

    /// Places the panel just below the anchor, or above it when there is no room, inside the visible screen.
    func layoutPanel() {
        let size = panelSize
        let screen = NSScreen.screens.first { NSMouseInRect(anchor.origin, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        var x = anchor.minX - 10 - PickerView.margin
        var y = anchor.minY - 6 + PickerView.margin - size.height
        if y < vf.minY { y = anchor.maxY + 6 }
        if userMoved {
            x = panel.frame.minX
            y = panel.frame.maxY - size.height
        }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        isLayingOut = true
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        isLayingOut = false
    }

    func hide() {
        panel.orderOut(nil)
        model.confirmingClear = false
        store.finalizeDelete()
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case kVK_Escape:
            if model.confirmingClear { model.confirmingClear = false } else { hide() }
        case kVK_ANSI_Comma where cmd:
            openSettings()
        case kVK_ANSI_Z where cmd:
            model.undoDelete()
        case kVK_UpArrow:
            model.move(-1)
        case kVK_DownArrow:
            model.move(1)
        case kVK_LeftArrow where cmd:
            model.stepKindFilter(-1)
        case kVK_RightArrow where cmd:
            model.stepKindFilter(1)
        case kVK_Tab:
            model.expanded.toggle()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selected {
                choose(item, plain: e.modifierFlags.contains(.option))
            }
        case kVK_Delete where cmd && e.modifierFlags.contains(.shift):
            if !store.items.isEmpty { model.confirmingClear = true }
        case kVK_Delete where cmd:
            if let item = model.selected { model.delete(item) }
        default:
            // By key position, so ⌘1–⌘9 also work on AZERTY and other layouts.
            let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                             kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
            guard cmd, let n = digitKeys.firstIndex(of: Int(e.keyCode)) else { return false }
            let items = model.filtered
            if items.count > n { choose(items[n]) }
        }
        return true
    }

    /// Puts the item on the clipboard and closes; you paste it yourself with ⌘V. No Accessibility
    /// permission is needed, so the app can't type into or read other apps.
    func choose(_ item: ClipItem, plain: Bool = false) {
        hide()
        store.copyToPasteboard(item, plain: plain)
    }

    // MARK: Menu bar

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Control+C")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openItem)
        menu.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(withTitle: L("Clear History…"), action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Control+C"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        openItem.title = L("Open Clipboard") + "   \(settings.shortcut.display)"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func openFromMenu() { DispatchQueue.main.async { self.show() } }

    @objc func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L("Clear your entire clipboard history?")
        alert.informativeText = L("All %d items will be deleted. This can’t be undone.", store.items.count)
        alert.addButton(withTitle: L("Clear All")).hasDestructiveAction = true
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { model.clearAll() }
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Control+C login item: \(error)")
        }
    }

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
