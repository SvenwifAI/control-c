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
        SecItemDelete(query as CFDictionary)
        return loadKey()
    }
}

/// Recognizes copied text that is probably a secret: one-time codes, API keys and tokens,
/// private keys, credentials in config lines and URLs, card numbers and password-like strings.
/// Such items are never written to disk. It is a best guess, tuned to rather flag too much than too little
/// for credentials, while leaving ordinary words, links, code and file names alone.
enum Secrets {
    /// How long a recognized secret stays in the list.
    static let lifetime: TimeInterval = 5 * 60

    static func looksSecret(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        if containsCredential(s) { return true }
        guard s.count <= 256, !s.contains(where: \.isNewline) else { return false }
        if isOneTimeCode(s) || isCardNumber(s) { return true }
        guard !s.contains(where: \.isWhitespace) else { return false }
        return looksLikePassword(s)
    }

    /// High-confidence credentials anywhere in a text, also in long or multi-line text and in text
    /// recognized in screenshots: private keys, known token formats, JWTs, `NAME=value` or
    /// `Password: value` lines, and URLs with a password in them.
    static func containsCredential(_ raw: String) -> Bool {
        let s = String(raw.prefix(65_536))
        if s.contains("PRIVATE KEY-----") { return true }
        if s.firstMatch(of: tokenPattern) != nil || s.firstMatch(of: jwtPattern) != nil { return true }
        if let m = s.firstMatch(of: #/[A-Za-z][A-Za-z0-9+.\-]*://[^\s/:@]+:([^\s/@]+)@/#), !m.1.isEmpty { return true }
        return s.split(whereSeparator: \.isNewline).contains { isCredentialLine(String($0)) }
    }

    // MARK: Building blocks

    /// Prefixes of tokens from common providers (GitHub, GitLab, Anthropic, OpenAI, Stripe, Slack, AWS,
    /// Google, SendGrid, Hugging Face, npm, PyPI, Shopify, DigitalOcean), followed by enough key material.
    private static let tokenPattern = #/(?:^|[^A-Za-z0-9])(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|glpat-|sk-ant-|sk-proj-|sk-|sk_live_|sk_test_|rk_live_|rk_test_|whsec_|xox[abeprs]-|xapp-|AKIA|ASIA|AIza|ya29\.|SG\.|hf_|npm_|pypi-|shpat_|shpss_|dop_v1_)[A-Za-z0-9_\-.]{14,}/#
    private static let jwtPattern = #/eyJ[A-Za-z0-9_\-]{6,}\.eyJ[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}/#

    /// Words in a setting's name that mark its value as a credential.
    private static let credentialNames = ["secret", "token", "password", "passwd", "passphrase", "pwd",
                                          "apikey", "api_key", "api-key", "accesskey", "access_key",
                                          "privatekey", "private_key", "credential", "wachtwoord", "pincode"]

    /// `export API_KEY=…`, `"token": "…"`, `DB_PASS=…`, `Wachtwoord: …`.
    private static func isCredentialLine(_ line: String) -> Bool {
        guard let m = line.firstMatch(of: #/^[\s{\[,]*(?:export\s+|set\s+)?["']?([A-Za-z][A-Za-z0-9_.\- ]{0,40}?)["']?\s*[:=]\s*["']?([^\s"',;]{4,})/#)
        else { return false }
        let name = m.1.lowercased().replacingOccurrences(of: " ", with: "")
        guard credentialNames.contains(where: name.contains) || name.hasSuffix("pass") || name == "pin" else { return false }
        let value = String(m.2)
        // Leave references, placeholders and booleans alone.
        if value.hasPrefix("$") || value.hasPrefix("<") || value.hasPrefix("{") || value.hasPrefix("%") { return false }
        return !["true", "false", "null", "none", "required", "optional", "changeme", "******", "xxxx"].contains(value.lowercased())
    }

    /// 6–8 digits, or 3+3 / 4+4 digits split by a space or dash.
    private static func isOneTimeCode(_ s: String) -> Bool {
        s.wholeMatch(of: #/\d{6,8}|\d{3}[ \-]\d{3}|\d{4}[ \-]\d{4}/#) != nil
    }

    /// 13–19 digits (spaces or dashes allowed) that pass the Luhn check.
    private static func isCardNumber(_ s: String) -> Bool {
        guard s.count <= 23, s.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == " " || $0 == "-" }) else { return false }
        let digits = s.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (i, d) = pair
            guard i % 2 == 1 else { return total + d }
            let doubled = d * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    /// A single word without spaces that looks generated or chosen as a password.
    private static func looksLikePassword(_ s: String) -> Bool {
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        // Apple's strong passwords: xupjo4-gyzZyc-bavkif.
        if s.wholeMatch(of: #/[A-Za-z0-9]{6}-[A-Za-z0-9]{6}-[A-Za-z0-9]{6}/#) != nil,
           s.contains(where: \.isUppercase), s.contains(where: isDigit) { return true }

        // Things that look random but are not secrets.
        if s.contains("://") || s.contains("@") && s.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/#) != nil { return false }
        if s.wholeMatch(of: #/\#?[0-9A-Fa-f]{3}|\#?[0-9A-Fa-f]{6}|\#[0-9A-Fa-f]{8}/#) != nil { return false }
        if s.wholeMatch(of: #/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/#) != nil { return false }
        if s.wholeMatch(of: #/[0-9a-f]{7,31}|[0-9a-f]{40}|[0-9a-f]{64}/#) != nil { return false } // hashes, commit ids
        if s.filter({ $0 == "/" }).count >= 2 || s.hasPrefix("~/") { return false } // paths
        if s.wholeMatch(of: #/[^\s]+\.[A-Za-z][A-Za-z0-9]{1,4}/#) != nil, !s.contains(where: isDigit) || s.contains("_") || s.contains("-") {
            // Looks like a file name or domain, e.g. report_2026.pdf or example.com.
            if s.split(separator: ".").last.map({ $0.allSatisfy(\.isLetter) || $0.count <= 4 }) == true,
               !s.contains(where: { !$0.isLetter && !isDigit($0) && !"._-".contains($0) }) { return false }
        }
        if s.wholeMatch(of: #/[A-Za-z_][\w.]*\(.*\);?/#) != nil { return false } // code such as items.reduce(0)
        if s.wholeMatch(of: #/v?\d+(\.\d+){1,3}([\-+][A-Za-z0-9.]+)?/#) != nil { return false } // version numbers
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
        let words = parts.filter { $0.count >= 2 && $0.allSatisfy(\.isLetter) }
        if parts.count >= 3, words.count >= 2 {
            // Slugs and identifiers written in one style: lower case (my_variable_name2) or each word
            // capitalized (Quarterly-Report-2026). Mixed styles (unruly-Dramatic-Stash4) look chosen.
            // The last part may be a code or number of its own (report-2026-final-B12).
            let lowerStyle = parts.dropLast().allSatisfy { p in p.allSatisfy { $0.isLowercase || isDigit($0) } }
            let titleStyle = parts.allSatisfy { p in
                p.allSatisfy(isDigit) || (p.first?.isUppercase == true && p.dropFirst().allSatisfy { $0.isLowercase || isDigit($0) })
            }
            if lowerStyle || titleStyle { return false }
        }
        // Reference codes: capitals and digits in separate groups (SKU-1234-AB, COVID-19).
        if parts.count >= 2, !s.contains(where: \.isLowercase),
           parts.allSatisfy({ p in p.allSatisfy(\.isUppercase) || p.allSatisfy(isDigit) }) { return false }
        // A word followed by a number (iPhone15, Windows11), unless symbols are mixed in.
        if s.wholeMatch(of: #/[A-Za-z]?[A-Z]?[a-z]+\d{1,4}/#) != nil { return false }

        let lower = s.contains(where: \.isLowercase), upper = s.contains(where: \.isUppercase)
        let digit = s.contains(where: isDigit), symbol = s.contains(where: { !$0.isLetter && !isDigit($0) })
        let classes = [lower, upper, digit, symbol].filter { $0 }.count

        // Long random-looking tokens: letters and digits mixed, maybe with -, _, +, / or =.
        if s.count >= 20, s.wholeMatch(of: #/[A-Za-z0-9_\-+\/=]+/#) != nil, (lower || upper), digit,
           parts.count <= 3 { return true }
        // Password-like: 8–64 characters, letters and digits, three of lower/upper/digits/symbols.
        guard (8...64).contains(s.count), lower || upper, digit else { return false }
        return classes >= 3
    }
}
