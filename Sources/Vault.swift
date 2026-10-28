// Protection for what you copy: encryption at rest, and recognizing secrets that should never be stored.

import Foundation
import CryptoKit
import Security

/// AES-256-GCM with a random key kept in the macOS Keychain, so the history on disk is unreadable
/// without it, whether that's another process, a backup or a copied disk.
enum Vault {
    private static let service = "com.svenvanrooijen.controlc"
    private static let account = "history-key"

    /// Loads the key, creating it on first launch. Nil when the Keychain refuses; the history then stays in memory only.
    static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            NSLog("Control+C: Keychain key unavailable (\(status)); history stays in memory")
            return nil
        }
        let key = SymmetricKey(size: .bits256)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Control+C history key",
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            NSLog("Control+C: could not store Keychain key (\(added)); history stays in memory")
            return nil
        }
        return key
    }

    /// Format byte in front of every sealed file. Version 1 binds the ciphertext to its file name,
    /// so one encrypted file can't be swapped in for another.
    private static let version: UInt8 = 1

    static func seal(_ data: Data, with key: SymmetricKey, context: String) -> Data? {
        guard let box = try? AES.GCM.seal(data, using: key, authenticating: Data("controlc:v1:\(context)".utf8)),
              let combined = box.combined else { return nil }
        return Data([version]) + combined
    }

    static func open(_ data: Data, with key: SymmetricKey, context: String) -> Data? {
        if data.first == version, let box = try? AES.GCM.SealedBox(combined: data.dropFirst()),
           let plain = try? AES.GCM.open(box, using: key, authenticating: Data("controlc:v1:\(context)".utf8)) {
            return plain
        }
        // Files from the first encrypted version: no format byte, no file binding.
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func isCurrentFormat(_ data: Data) -> Bool { data.first == version }

    /// Deletes the key and makes a new one, so copies of old files (backups, snapshots) can no longer be read.
    static func rotateKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // If the old key can't be removed, don't pretend it was replaced: stop writing instead.
        guard status == errSecSuccess || status == errSecItemNotFound else { return nil }
        return loadKey()
    }
}

/// Recognizes copied text that is probably a secret: one-time and recovery codes, API keys and tokens,
/// private keys, credentials in config files, URLs and notes, card numbers and password-like strings.
enum Secrets {
    /// How long a recognized secret stays in the list.
    static let lifetime: TimeInterval = 5 * 60

    static func looksSecret(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        // Very large copies: only the start is examined, so the check stays instant.
        if containsSecret(s.utf8.count > 65_536 ? String(s.prefix(65_536)) : s) { return true }
        if s.utf8.count <= 4096, isSpacedCode(s) || isSeedPhrase(s) || isCodeList(s) { return true }
        guard s.count <= 256, !s.contains(where: \.isWhitespace) else { return false }
        // A value copied with its quotes or a trailing comma from code or JSON: judge the value itself.
        let bare = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;[]"))
        return !bare.isEmpty && isSecretToken(bare)
    }

    /// Credentials that are unmistakable wherever they appear, for longer text such as the text recognized
    /// in a screenshot: private keys, known tokens, labelled passwords and keys, URLs with a password, cards.
    static func containsCredential(_ raw: String) -> Bool {
        containsSecret(raw.utf8.count > 65_536 ? String(raw.prefix(65_536)) : raw)
    }

    // MARK: Anywhere in the text: notes, .env files, config, commands, code

    private static func containsSecret(_ t: String) -> Bool {
        if t.contains("-----BEGIN"), t.contains("PRIVATE KEY") { return true }
        if t.contains("PuTTY-User-Key-File-") || t.contains("AGE-SECRET-KEY-1") { return true }
        return hasKnownToken(t) || hasLabelledSecret(t) || hasCardNumber(t)
    }

    /// Token formats by their fixed start, matched at the start of a word or right after its `=` or `:`.
    private static let knownTokens: [Character: [(String, Regex<Substring>)]] = Dictionary(grouping: [
        ("sk-", #/sk-(?:ant-[a-z]+\d\d-[A-Za-z0-9_-]{32,}|(?:proj|svcacct|admin|None)-[A-Za-z0-9_-]{32,}|[A-Za-z0-9]{32,})/#), // Anthropic, OpenAI
        ("sk_", #/sk_(?:live|test)_[A-Za-z0-9]{16,}/#), ("rk_", #/rk_(?:live|test)_[A-Za-z0-9]{16,}/#), // Stripe
        ("whsec_", #/whsec_[A-Za-z0-9+\/=]{24,}/#),
        ("gh", #/gh[pousr]_[A-Za-z0-9]{30,}/#), ("github_pat_", #/github_pat_[A-Za-z0-9_]{50,}/#),
        ("gl", #/gl(?:pat|ptt|dt|rt|soat|cbt|ft|imt|agent|oas)-[A-Za-z0-9_-]{20,}/#), ("GR1348941", #/GR1348941[A-Za-z0-9_-]{20,}/#),
        ("xox", #/xox[abposre][-.][A-Za-z0-9.-]{10,}/#), ("xapp-", #/xapp-\d-[A-Za-z0-9-]{20,}/#), // Slack
        ("AKIA", #/AKIA[A-Z0-9]{16}(?![A-Za-z0-9])/#), ("ASIA", #/ASIA[A-Z0-9]{16}(?![A-Za-z0-9])/#), // AWS
        ("IQoJb3JpZ2luX2Vj", #/IQoJb3JpZ2luX2Vj[A-Za-z0-9\/+=]{100,}/#), ("FwoGZXIvYXdzE", #/FwoGZXIvYXdzE[A-Za-z0-9\/+=]{100,}/#),
        ("AIza", #/AIza[0-9A-Za-z_-]{35}/#), ("ya29.", #/ya29\.[0-9A-Za-z_-]{20,}/#), // Google
        ("GOCSPX-", #/GOCSPX-[A-Za-z0-9_-]{20,}/#), ("1//0", #/1\/\/0[A-Za-z0-9_-]{40,}/#),
        ("AccountKey=", #/AccountKey=[A-Za-z0-9+\/]{40,}/#), ("SharedAccessKey=", #/SharedAccessKey=[A-Za-z0-9+\/]{20,}/#), // Azure
        ("SG.", #/SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/#), ("key-", #/key-[0-9a-z]{32}(?![0-9a-z])/#), // SendGrid, Mailgun
        ("hf_", #/hf_[A-Za-z0-9]{30,}/#), ("npm_", #/npm_[A-Za-z0-9]{30,}/#), ("pypi-", #/pypi-[A-Za-z0-9_-]{50,}/#),
        ("shp", #/shp(?:at|ss|ca|pa)_[a-fA-F0-9]{32}/#), ("do", #/do[opr]_v1_[a-f0-9]{64}/#),
        ("dckr_pat_", #/dckr_pat_[A-Za-z0-9_-]{20,}/#), ("sbp_", #/sbp_[a-f0-9]{40}/#),
        ("xai-", #/xai-[A-Za-z0-9]{40,}/#), ("gsk_", #/gsk_[A-Za-z0-9]{40,}/#), ("r8_", #/r8_[A-Za-z0-9]{30,}/#),
        ("pplx-", #/pplx-[A-Za-z0-9]{40,}/#), ("lin_api_", #/lin_api_[A-Za-z0-9]{30,}/#), ("ntn_", #/ntn_[A-Za-z0-9]{30,}/#),
        ("ATATT", #/ATATT[A-Za-z0-9_=-]{50,}/#), ("dp.", #/dp\.(?:st|ct|sa|scim|audit|pt)\.[A-Za-z0-9_.-]{30,}/#),
        ("ops_eyJ", #/ops_eyJ[A-Za-z0-9_-]{30,}/#), ("PMAK-", #/PMAK-[a-f0-9]{24}-[a-f0-9]{34}/#),
        ("eyJ", #/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*/#), // JWT
        ("otpauth", #/otpauth(?:-migration)?:\/\/\S*?[?&](?:secret|data)=/#), // 2FA seed
    ] as [(String, Regex<Substring>)], by: { $0.0.first! })
    private static let telegramBot = #/\d{8,10}:AA[A-Za-z0-9_-]{33}/#
    private static let discordBot = #/[MNO][A-Za-z0-9_-]{23,27}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,40}/#
    private static let webhook = #/(?:hooks\.slack\.com\/(?:services|workflows|triggers)\/|discord(?:app)?\.com\/api\/webhooks\/\d+\/|\.webhook\.office\.com\/webhookb2\/)[A-Za-z0-9_\/@-]{20,}/#
    /// The scheme is bounded: an unbounded `[A-Za-z0-9+.-]*://` backtracks quadratically on long tokens.
    private static let urlCredentials = #/[A-Za-z][A-Za-z0-9+.-]{0,30}:\/\/([^\s\/:@]*):([^\s\/@]+)@/#
    private static let secretParam = #/(?i)[?&#](?:access_token|id_token|refresh_token|auth_token|token|api_?key|apikey|key|secret|client_secret|password|passwd|sig|signature|x-amz-signature|x-goog-signature)=([^&\s#]{16,})/#

    private static func hasKnownToken(_ t: String) -> Bool {
        for word in t.split(whereSeparator: { $0.isWhitespace || "\"'`,;()[]{}<>|\\".contains($0) }) where word.count >= 16 {
            var candidates = [word]
            var rest = word[...]
            while let i = rest.firstIndex(where: { $0 == "=" || $0 == ":" }) {
                rest = rest[rest.index(after: i)...]
                if rest.utf8.count >= 16 { candidates.append(rest) } // utf8.count is O(1) on these
                if candidates.count > 8 { break } // a=a=a=… would otherwise make this quadratic
            }
            for c in candidates {
                guard let first = c.first else { continue }
                if knownTokens[first]?.contains(where: { c.hasPrefix($0.0) && c.prefixMatch(of: $0.1) != nil }) == true { return true }
                if first.isNumber, c.prefixMatch(of: telegramBot) != nil { return true }
                if "MNO".contains(first), c.wholeMatch(of: discordBot) != nil { return true }
            }
            guard word.count <= 4096, word.contains("://") || word.contains("=") else { continue }
            if word.contains("://") {
                if word.contains(webhook) { return true }
                if word.matches(of: urlCredentials).contains(where: { isCredential($0.2, .password, quoted: true, code: false) }) { return true }
            }
            if word.matches(of: secretParam).contains(where: { $0.1.contains(where: \.isNumber) }) { return true }
        }
        return false
    }

    // Labelled values. Each pattern is tried only where its label starts, never across the whole text.
    /// `password: x`, `API_KEY=x`, `"token": "x"`, `Password=x;` (connection strings), `db_password: x`.
    private static let labelled = #/(?i)(password|passwd|passwort|passphrase|wachtwoord|pwd|pass|pw|pincode|pin|client[_-]?secret|secret[_-]?key|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key|auth[_-]?token|access[_-]?token|refresh[_-]?token|token|session[_-]?id|sessionid|session)["']?\s*(?::=|=>|:|=)\s*(["'`]?)([^\s"'`,;]+)/#
    /// Environment variables such as PGPASSWORD or STRIPE_SECRET_KEY, from the start of the name.
    private static let envLabelled = #/[A-Z][A-Z0-9_]{0,40}?(PASSWORD|PASSWD|PWD|SECRET|TOKEN|APIKEY|API_KEY|ACCESS_KEY|PRIVATE_KEY)\s*=\s*(["']?)([^\s"'`,;]+)/#
    /// "Your temporary password is X7#kd92Q", "Je verificatiecode is 482913".
    private static let prose = #/(?i)(password|passcode|passphrase|wachtwoord|pincode|code)\s+(?:is|luidt|was)\s*:?\s*["'`]?([^\s"'`]+)/#
    /// `curl -u name:password`, `--user name:password`.
    private static let curlUser = #/(?:^|\s)(?:-u|--user)\s+["']?[^\s:"']+:([^\s"'@]{4,})/#
    /// A line that is only a password label, as in forms and screenshots: the value is on the next line.
    private static let bareLabel = #/(?i)\s*(?:password|wachtwoord|passcode|pincode|pin)\s*:?\s*/#
    private static let authHeader = #/(?i)(?:bearer|basic)\s+([A-Za-z0-9._~+\/-]{16,}=*)/#
    private static let bsn = #/(?i)(?:bsn|burgerservicenummer|sofi-?nummer)\b\D{0,5}(\d{4}\.\d{2}\.\d{3}|\d{3} \d{3} \d{3}|\d{9})(?![0-9])/#
    private static let labelWords = ["pass", "pw", "wachtwoord", "secret", "token", "key", "pin", "session", "bearer", "basic",
                                     "code", "bsn", "burgerservice", "sofi"]

    /// Where one of `words` (lowercase ASCII) starts in `line`, in any case; not in the middle of a word unless `inside`.
    private static func starts(of words: [String], in line: Substring, inside: Bool = false) -> [Substring.Index] {
        let bytes = Array(line.utf8), needles = words.map { Array($0.utf8) }
        func lower(_ b: UInt8) -> UInt8 { (65...90).contains(b) ? b + 32 : b }
        func isWordByte(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b) || b >= 128 }
        var result: [Substring.Index] = []
        for i in bytes.indices where inside || i == 0 || !isWordByte(bytes[i - 1]) {
            let b = lower(bytes[i])
            if needles.contains(where: { n in n[0] == b && i + n.count <= bytes.count && (1..<n.count).allSatisfy { lower(bytes[i + $0]) == n[$0] } }) {
                result.append(line.utf8.index(line.startIndex, offsetBy: i))
            }
        }
        return result
    }

    private static func hasLabelledSecret(_ t: String) -> Bool {
        let lowerText = t.lowercased()
        guard labelWords.contains(where: lowerText.contains) else { return false }
        let code = ["{", "}", "=>", "->", "();", "func ", "def ", "const ", "let ", "var ", "import ", "function ", "return ",
                    "self.", "this."].contains(where: t.contains)
        let otpHint = ["share", "deel deze", "niet delen", "expire", "verloopt", "geldig"].contains(where: lowerText.contains)
        let allLines = t.split(whereSeparator: \.isNewline)
        for (n, line) in allLines.prefix(4000).enumerated() where line.wholeMatch(of: bareLabel) != nil && n + 1 < allLines.count {
            let value = allLines[n + 1].trimmingCharacters(in: .whitespaces)
            if !value.contains(" "), value.count >= 6, value.contains(where: \.isLetter),
               value.contains(where: { !$0.isLetter }), isCredential(Substring(value), .password, quoted: true, code: false) {
                return true
            }
        }
        for line in allLines.prefix(4000) {
            let lower = line.lowercased()
            guard labelWords.contains(where: lower.contains) else { continue }
            for i in starts(of: ["pass", "pw", "pin", "secret", "api", "access", "private", "auth", "refresh", "token", "session", "client", "wachtwoord"], in: line) {
                if let m = line[i...].prefixMatch(of: labelled), isCredential(m.3, kind(of: m.1), quoted: !m.2.isEmpty, code: code) { return true }
            }
            if line.contains("=") {
                for i in starts(of: ["pass", "pwd", "secret", "token", "key"], in: line, inside: true) {
                    var j = i // back to the start of the name
                    while j > line.startIndex, let c = line[line.index(before: j)].asciiValue, c == 95 || (65...90).contains(c) || (48...57).contains(c) {
                        j = line.index(before: j)
                    }
                    if let m = line[j...].prefixMatch(of: envLabelled), isCredential(m.3, kind(of: m.1), quoted: !m.2.isEmpty, code: code) { return true }
                }
            }
            for i in starts(of: ["password", "passcode", "passphrase", "wachtwoord", "code"], in: line, inside: true) {
                guard let m = line[i...].prefixMatch(of: prose) else { continue }
                let value = m.2.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
                let label = m.1.lowercased()
                if label == "code" || label == "pincode" {
                    // A one-time code needs words that say so: "postcode is 1234 AB" and "error code is 404" are not.
                    let before = line[(line.index(i, offsetBy: -16, limitedBy: line.startIndex) ?? line.startIndex)..<i]
                        .lowercased().trimmingCharacters(in: .whitespaces)
                    let otp = otpHint || label == "pincode"
                        || ["verificatie", "verification", "security", "beveiligings", "login", "inlog", "bevestigings", "sms",
                            "2fa", "otp", "toegangs", "access", "eenmalige", "one-time", "auth", "your", "je", "uw"].contains(where: before.hasSuffix)
                    if otp, value.wholeMatch(of: #/\d{4,8}/#) != nil { return true }
                } else if value.count >= 6, value.contains(where: \.isLetter),
                          value.contains(where: { $0.isNumber || (!$0.isLetter && !"-'.".contains($0)) }),
                          isCredential(m.2, .password, quoted: true, code: false) {
                    return true
                }
            }
            if let m = line.firstMatch(of: curlUser), isCredential(m.1, .password, quoted: false, code: false) { return true }
            for i in starts(of: ["bearer", "basic"], in: line) {
                if let m = line[i...].prefixMatch(of: authHeader), m.1.contains(where: \.isNumber) { return true }
            }
            for i in starts(of: ["bsn", "burgerservicenummer", "sofi"], in: line) {
                if let m = line[i...].prefixMatch(of: bsn), isBSN(m.1.filter(\.isNumber)) { return true }
            }
        }
        return false
    }

    /// Card numbers in a text: in groups (4-4-4-4, Amex 4-6-5) anywhere, or 13–19 digits in one piece in a short text.
    private static func hasCardNumber(_ t: String) -> Bool {
        var digits: [Int] = [], groups: [Int] = [], pendingSeparator = false, startsClean = true
        var previous: Character = " "
        func ends(cleanly: Bool) -> Bool {
            defer { digits = []; groups = []; pendingSeparator = false }
            guard startsClean, cleanly || pendingSeparator, digits.count >= 13 else { return false }
            if groups.count == 1 { return t.count <= 200 && isCard(digits) }
            let shapes: [[Int]] = [[4, 4, 4, 4], [4, 6, 5], [4, 6, 4]]
            for shape in shapes where Array(groups.prefix(shape.count)) == shape {
                let n = shape.reduce(0, +)
                if isCard(Array(digits.prefix(n))) { return true }
                if shape.count == 4, groups.count > 4, groups[4] <= 3, isCard(Array(digits.prefix(n + groups[4]))) { return true }
            }
            return false
        }
        for ch in t {
            if ch.isASCII, let d = ch.wholeNumberValue {
                if digits.isEmpty { startsClean = !(previous.isLetter || previous.isNumber) }
                if digits.isEmpty || pendingSeparator { groups.append(1) } else { groups[groups.count - 1] += 1 }
                digits.append(d)
                pendingSeparator = false
            } else if (ch == " " || ch == "-"), !digits.isEmpty, !pendingSeparator {
                pendingSeparator = true
            } else if !digits.isEmpty {
                if ends(cleanly: !(ch.isLetter || ch.isNumber)) { return true }
            }
            previous = ch
        }
        return !digits.isEmpty && ends(cleanly: true)
    }

    private enum Kind { case password, loose, pin, token }

    private static func kind(of key: Substring) -> Kind {
        switch key.lowercased() {
        case "pass", "pw": .loose
        case "pin", "pincode": .pin
        case "password", "passwd", "passwort", "passphrase", "wachtwoord", "pwd": .password
        default: .token
        }
    }

    private static let placeholders: Set<String> = [
        "string", "str", "int", "integer", "number", "bool", "boolean", "any", "unknown", "text", "data", "char", "varchar",
        "bytes", "secretstr", "securestring", "optional", "nullable", "required", "none", "null", "nil", "undefined",
        "true", "false", "yes", "no", "on", "off", "hidden", "redacted", "empty", "n/a", "tbd", "todo", "test",
        "changeme", "change_me", "password", "wachtwoord", "secret", "token", "pass", "passwd", "example", "dummy", "placeholder",
    ]

    /// Whether a labelled value is an actual credential rather than a type, variable, reference or placeholder.
    private static func isCredential(_ raw: Substring, _ kind: Kind, quoted: Bool, code: Bool) -> Bool {
        var v = String(raw)
        if !quoted { while let last = v.last, ".)]}".contains(last), v.count > 4 { v.removeLast() } }
        let lower = v.lowercased()
        guard v.count >= 4, !placeholders.contains(lower),
              !placeholders.contains(lower.trimmingCharacters(in: CharacterSet(charactersIn: "?![]"))),
              let first = v.first, !"$<{%[(*•".contains(first), !v.hasPrefix("/"), !v.hasPrefix("~/"),
              !v.allSatisfy({ "*xX•.#-_".contains($0) }),
              !["your", "insert", "replace", "example", "<", "!ref", "!sub", "!getatt", "process.env", "os.environ", "os.getenv",
                "getenv", "env.", "env[", "env(", "secrets.", "vars.", "config.", "settings.", "self.", "this.", "req.",
                "request.", "params.", "options.", "props.", "args."].contains(where: lower.hasPrefix)
        else { return false }
        if !quoted {
            if v.contains("(") { return false } // a call, such as z.string().min(8)
            if v.wholeMatch(of: #/[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+/#) != nil { return false } // a.b.c
            if code, v.wholeMatch(of: #/[A-Za-z_]\w*[?!]?/#) != nil { return false } // a variable or type in code
        }
        switch kind {
        case .password: return true
        case .loose: return v.count >= 6 && v.contains { !$0.isLetter }
        case .pin: return v.wholeMatch(of: #/\d{4,8}/#) != nil
        case .token: return v.count >= 12 && (v.contains(where: \.isNumber) || v.count >= 20)
            && !v.allSatisfy { $0.isLowercase || $0 == "-" || $0 == "_" }
        }
    }

    // MARK: Whole-text shapes with spaces or lines

    /// "123 456", "1234 5678" (Google backup code), a TOTP seed as sites show it ("jbsw y3dp ehpk 3pxp").
    private static func isSpacedCode(_ s: String) -> Bool {
        if s.wholeMatch(of: #/\d{3} \d{3}|\d{4} \d{4}/#) != nil { return true }
        return s.wholeMatch(of: #/(?:[A-Za-z2-7]{4} ){3,}[A-Za-z2-7]{2,4}/#) != nil && s.filter(\.isNumber).count >= 2
    }

    /// A crypto wallet recovery phrase: 12–24 short lowercase words, none of them common in sentences.
    private static func isSeedPhrase(_ s: String) -> Bool {
        let words = s.split(whereSeparator: \.isWhitespace)
        guard [12, 15, 18, 21, 24].contains(words.count) else { return false }
        // Recovery phrases (BIP39) avoid everyday function words; a normal sentence always has some.
        let common: Set<Substring> = ["the", "and", "for", "are", "with", "your", "from", "have", "that", "this",
                                      "these", "those", "was", "were", "would", "could", "should", "please", "our", "its",
                                      "his", "her", "they", "them", "what", "when", "where", "which", "who", "how", "not",
                                      "but", "into", "than", "there", "here", "thanks",
                                      "het", "een", "dat", "die", "niet", "ook", "maar", "voor", "naar", "met", "wat",
                                      "wie", "hoe", "waar", "als", "dan", "nog", "heb", "hebt", "heeft", "ben", "bent",
                                      "zijn", "kan", "kun", "wil", "mijn", "jouw", "onze", "deze", "graag", "bedankt"]
        return words.allSatisfy { w in (3...8).contains(w.count) && w.allSatisfy { $0.isASCII && $0.isLowercase } && !common.contains(w) }
    }

    /// A block of recovery codes, or several secrets one per line.
    private static func isCodeList(_ s: String) -> Bool {
        let lines = s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).replacing(#/^(?:\d{1,2}[.)]|[-•*])\s*/#, with: "") }
            .filter { !$0.isEmpty }
        guard (2...64).contains(lines.count) else { return false }
        if lines.allSatisfy({ $0.wholeMatch(of: #/[A-Za-z0-9]{4,6}[- ][A-Za-z0-9]{4,6}/#) != nil }) {
            let digits = lines.filter { $0.contains(where: \.isNumber) }.count
            let letters = lines.filter { $0.contains(where: \.isLetter) }.count
            if letters == 0 || (digits * 2 >= lines.count && letters * 2 >= lines.count) { return true }
        }
        return lines.allSatisfy { $0.count <= 256 && !$0.contains(where: \.isWhitespace) && isSecretToken($0) }
    }

    // MARK: A single token

    private static func isSecretToken(_ s: String) -> Bool {
        // One-time codes (6 digits; longer bare numbers are order, KvK and phone numbers), backup and recovery codes.
        if s.wholeMatch(of: #/\d{6}|\d{3}-\d{3}|[A-Z]-\d{6}|\d{4}-\d{4}/#) != nil { return true }
        if s.allSatisfy({ $0.isASCII && $0.isNumber }) { return isCard(s.compactMap(\.wholeNumberValue)) }
        if s.wholeMatch(of: #/[0-9a-f]{5}-[0-9a-f]{5}|A3(?:-[A-Z0-9]{5,6}){5,6}/#) != nil { return true } // GitHub, 1Password
        if let m = s.wholeMatch(of: #/[A-Z0-9]{4,6}(?:-[A-Z0-9]{4,6})+|[a-z0-9]{4,6}(?:-[a-z0-9]{4,6})+/#) {
            let groups = m.0.split(separator: "-")
            let mixed = groups.filter { $0.contains(where: \.isLetter) && $0.contains(where: \.isNumber) }.count
            if mixed == groups.count || (groups.count >= 4 && mixed > 0) { return true } // Microsoft, Apple recovery keys
        }
        if s.wholeMatch(of: #/[A-Za-z0-9]{6}-[A-Za-z0-9]{6}-[A-Za-z0-9]{6}/#) != nil, s.contains(where: \.isUppercase),
           s.contains(where: \.isLowercase), s.contains(where: \.isNumber) { return true } // Apple-generated password
        if s.wholeMatch(of: #/[A-Z2-7]{16,}=*/#) != nil, s.filter(\.isNumber).count >= 2,
           s.count % 8 == 0 || s.count >= 26 { return true } // TOTP seed (base32)
        if s.wholeMatch(of: #/[A-Z][a-z]{2,}\d{0,2}(?:[-_.+~][A-Z][a-z]{2,}\d{0,2}){2,}(?:[-_.+~]\d{1,4})?/#) != nil,
           s.contains(where: \.isNumber) { return true } // passphrase with a number ("Snowfall-Mantis-Crawl6")
        if s.wholeMatch(of: #/[A-Za-z0-9\/+]{40}/#) != nil, s.contains(where: \.isUppercase), s.contains(where: \.isLowercase),
           s.contains(where: \.isNumber), s.contains("+") || caseSwitches(s) >= 8 { return true } // AWS secret access key
        // KEY=VALUE: judge the value (names that announce a secret were judged above).
        if let m = s.wholeMatch(of: #/[A-Za-z_][A-Za-z0-9_.-]*=(.+)/#) { return isSecretToken(String(m.1)) }

        if s.contains("://") || s.hasPrefix("~/") || isPath(s) || isColor(s) || isCode(s) || isOrdinary(s) { return false }

        let hasLetter = s.contains(where: \.isLetter), hasDigit = s.contains(where: { $0.isASCII && $0.isNumber })
        // Letters no language puts together (five consonants in a row): generated, not typed.
        if s.count >= 10, hasLetter, longestConsonantRun(s) >= 5,
           hasDigit || s.contains(where: { !$0.isLetter && !$0.isNumber }) || caseSwitches(s) >= 3 { return true }
        // Generated passwords without digits: upper, lower and symbols, with the case jumping around.
        if (10...64).contains(s.count), s.contains(where: \.isUppercase), s.contains(where: \.isLowercase),
           s.contains(where: { !$0.isLetter && !$0.isNumber }), caseSwitches(s) >= 3 { return true }
        // Long random strings: keys and tokens without a known prefix.
        if s.count >= 24, s.wholeMatch(of: #/[A-Za-z0-9_+\/=-]+/#) != nil, hasLetter, hasDigit { return true }
        // Long generated passwords with symbols.
        if s.count > 64, hasLetter, hasDigit, s.contains(where: { !$0.isLetter && !$0.isNumber }),
           s.contains(where: \.isUppercase), s.contains(where: \.isLowercase), caseSwitches(s) * 4 >= s.count { return true }
        // Random lowercase letters and digits, as some generators make.
        if (16...23).contains(s.count), s.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }),
           s.filter(\.isNumber).count >= 3, transitions(s) >= 5 { return true }
        // Password-like: 8–64 characters with letters and digits, using at least three of lower, upper,
        // digits and symbols. Code such as `items.reduce(0)` is not a password.
        guard (8...64).contains(s.count), hasLetter, hasDigit,
              s.wholeMatch(of: #/[A-Za-z_][\w.]*\(.*\);?/#) == nil else { return false }
        let classes = [
            s.contains(where: { $0.isLowercase }),
            s.contains(where: { $0.isUppercase }),
            hasDigit,
            s.contains(where: { !$0.isLetter && !$0.isNumber }),
        ].filter { $0 }.count
        return classes >= 3
    }

    private static let separators: Set<Character> = ["-", "_", ".", "/", ":", ",", "\\"]

    /// Things that look random but are not secrets.
    private static let ordinaryShapes: [Regex<Substring>] = [
        #/[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/#, // email
        #/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/#, // UUID
        #/[0-9a-f]{40}|[0-9a-f]{24}/#, // git commit, MongoDB id
        #/\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?/#, // ISO date and time
        #/@?[A-Za-z0-9._\/-]+@[\^~]?v?\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.-]+)?/#, // package@1.2.3
        #/[vV]?\d+(?:\.\d+)+(?:[-+][0-9A-Za-z.-]+)?/#, // version
        #/0[xX][0-9A-Fa-f]{1,16}|0x[0-9a-fA-F]{40}/#, // hex literal, Ethereum address
        #/(?:bc1|tb1)[02-9ac-hj-np-z]{11,71}|[13][1-9A-HJ-NP-Za-km-z]{25,34}/#, // Bitcoin address
        #/(?:cus|pi|ch|pm|in|sub|prod|price|evt|acct|txn|re|src|seti|py|po|tr|ii|il|si|req|file|cs|pk_live|pk_test)_[A-Za-z0-9]{8,}/#, // Stripe ids
        #/[A-Za-z]+\d+,\d+/#, // Mac model identifier
        #/(?i)[^\/\\\s]+\.(?:pdf|png|jpe?g|gif|heic|webp|svg|tiff?|txt|md|rtf|csv|tsv|xlsx?|docx?|pptx?|key|pages|numbers|zip|dmg|pkg|json|ya?ml|toml|xml|plist|swift|m|h|c|cpp|js|mjs|ts|tsx|jsx|py|rb|go|rs|java|kt|php|sh|html?|css|scss|sql|log|mov|mp4|mp3|wav|m4a|ics|vcf|eml)/#, // file name
        #/(?i)(?:localhost|(?:\d{1,3}\.){3}\d{1,3}|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,24})(?::\d{1,5})?(?:[\/?#]\S*)?/#, // host[:port][/path]
    ]

    private static func isOrdinary(_ s: String) -> Bool {
        if ordinaryShapes.contains(where: { s.wholeMatch(of: $0) != nil }) || s.hasPrefix("arn:") || isIBAN(s) { return true }
        // Built from words and numbers only: slugs, file and branch names, product names, ticket and order numbers.
        guard s.allSatisfy({ $0.isLetter || $0.isNumber || separators.contains($0) }) else { return false }
        if s.split(whereSeparator: { separators.contains($0) }).allSatisfy(isWordish) { return true }
        // Lowercase ids such as pod names, instance ids and region names.
        let parts = s.split(whereSeparator: { separators.contains($0) })
        return !s.contains(where: \.isUppercase) && parts.count > 1 && parts.allSatisfy { $0.count <= 20 }
    }

    /// Words, numbers and short acronyms joined together: "invoice", "2026", "iPhone15", "Q4", "Win10Pro",
    /// "MacBookPro2024", "SM-G991B". Random letters ("FcrkvcJ5MW") fail: their pieces don't read like words.
    private static let wordPiece = #/\p{Lu}+(?!\p{Ll})|\p{Lu}?\p{Ll}+|\d+/#
    private static func isWordish(_ part: Substring) -> Bool {
        let pieces = part.matches(of: wordPiece).map { String($0.0) }
        guard pieces.joined().count == part.count, (1...5).contains(pieces.count) else { return false }
        return pieces.enumerated().allSatisfy { i, piece in
            if piece.allSatisfy(\.isNumber) { return true }
            if piece.allSatisfy(\.isUppercase) { return piece.count <= 6 } // acronym: HTTP, Q, COVID
            if piece.count == 1 { return true } // the i in iPhone, the x in x264
            // Two letters right after a number ("hunter2Ab") look random; after a word ("ById") they don't.
            if piece.count == 2, i > 0, pieces[i - 1].allSatisfy(\.isNumber) { return false }
            return piece.lowercased().contains(where: vowels.contains) && longestConsonantRun(piece) < 5
        }
    }

    private static let vowels: Set<Character> = Set("aeiouyàáâäèéêëìíîïòóôöùúûüÿ")

    private static func longestConsonantRun<S: StringProtocol>(_ s: S) -> Int {
        var longest = 0, run = 0
        for c in s.lowercased() {
            if c.isLetter, !vowels.contains(c) { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        return longest
    }

    private static func isPath(_ s: String) -> Bool { s.hasPrefix("/") && s.dropFirst().contains("/") }
    private static func isColor(_ s: String) -> Bool {
        s.wholeMatch(of: #/\#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})/#) != nil
    }
    /// Code such as `.padding(20)`, `items.reduce(0)` or `$0.name.count`.
    private static func isCode(_ s: String) -> Bool {
        s.wholeMatch(of: #/[.$]?[A-Za-z_$0-9][\w.$?!]*(?:\(.*\))?[;,]?/#) != nil
            && (s.contains("(") || s.hasPrefix(".") || s.hasPrefix("$") || s.contains("?."))
    }

    /// Changes between upper- and lowercase letters next to each other: many in random strings, few in words.
    private static func caseSwitches(_ s: String) -> Int {
        zip(s, s.dropFirst()).filter { $0.isLetter && $1.isLetter && $0.isUppercase != $1.isUppercase }.count
    }

    private static func transitions(_ s: String) -> Int {
        zip(s, s.dropFirst()).filter { $0.isNumber != $1.isNumber }.count
    }

    /// 13–19 digits from a card issuer range that pass the Luhn check.
    private static func isCard(_ d: [Int]) -> Bool {
        guard (13...19).contains(d.count), (2...6).contains(d[0]) else { return false }
        let two = d[0] * 10 + d[1], four = two * 100 + d[2] * 10 + d[3]
        if d[0] == 2, !(2221...2720).contains(four) { return false } // Mastercard 2-series only
        if d[0] == 3, ![30, 34, 35, 36, 37, 38, 39].contains(two) { return false }
        switch d.count {
        case 13: guard d[0] == 4 else { return false }
        case 14: guard [30, 36, 38].contains(two) else { return false }
        case 15: guard two == 34 || two == 37 else { return false } // Amex; also rules out IMEI numbers
        default: break
        }
        let sum = d.reversed().enumerated().reduce(0) { total, pair in
            let (i, x) = pair
            guard i % 2 == 1 else { return total + x }
            return total + (x * 2 > 9 ? x * 2 - 9 : x * 2)
        }
        return sum % 10 == 0
    }

    /// Dutch citizen service number: 9 digits passing the 11-proof.
    private static func isBSN(_ digits: String) -> Bool {
        let d = digits.compactMap(\.wholeNumberValue)
        guard d.count == 9 else { return false }
        let sum = (0..<8).reduce(0) { $0 + (9 - $1) * d[$1] } - d[8]
        return sum % 11 == 0 && sum != 0
    }

    /// An IBAN with a valid checksum: not a secret, people share it to get paid.
    private static func isIBAN(_ s: String) -> Bool {
        guard s.wholeMatch(of: #/[A-Z]{2}\d{2}[A-Z0-9]{11,30}/#) != nil else { return false }
        let rearranged = s.dropFirst(4) + s.prefix(4)
        var remainder = 0
        for c in rearranged {
            let v = c.isNumber ? Int(String(c))! : Int(c.asciiValue! - 55)
            remainder = (v < 10 ? remainder * 10 + v : remainder * 100 + v) % 97
        }
        return remainder == 1
    }
}
