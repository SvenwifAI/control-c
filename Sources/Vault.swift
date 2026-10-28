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

    static func seal(_ data: Data, with key: SymmetricKey) -> Data? {
        try? AES.GCM.seal(data, using: key).combined
    }

    static func open(_ data: Data, with key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

/// Recognizes copied text that is probably a secret: one-time codes, API keys and tokens,
/// private keys, card numbers and password-like strings. Such items are never written to disk.
enum Secrets {
    /// How long a recognized secret stays in the list.
    static let lifetime: TimeInterval = 5 * 60

    static func looksSecret(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("-----BEGIN"), s.contains("PRIVATE KEY") { return true }
        if isCardNumber(s) { return true }
        guard !s.isEmpty, s.count <= 256, !s.contains(where: \.isWhitespace) else { return false }

        // One-time codes: 6–8 digits, or "123-456".
        if s.wholeMatch(of: #/\d{6,8}|\d{3}[- ]\d{3}/#) != nil { return true }

        // Well-known token formats (GitHub, OpenAI/Anthropic-style, Stripe, Slack, AWS, Google, JWT, ...).
        if s.count >= 16, s.prefixMatch(of: #/(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|glpat-|sk-|sk_live_|sk_test_|rk_live_|xox[abprs]-|AKIA|ASIA|AIza|ya29\.|SG\.|hf_|npm_|shpat_|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.)/#) != nil {
            return true
        }

        // Things that look random but are not secrets.
        // Slugs and file-like names ("invoice-2026-october-final"): several parts, at least two of them words.
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
        if parts.count >= 3, parts.filter({ $0.count >= 2 && $0.allSatisfy(\.isLetter) }).count >= 2 { return false }
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") || s.hasPrefix("#") { return false }
        if s.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/#) != nil { return false }
        if s.wholeMatch(of: #/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/#) != nil { return false }
        if s.wholeMatch(of: #/[0-9a-f]{40}/#) != nil { return false } // git commit hash

        // Long random-looking tokens: letters and digits mixed, no separators.
        if s.count >= 24, s.wholeMatch(of: #/[A-Za-z0-9_\-]+/#) != nil,
           s.contains(where: \.isLetter), s.contains(where: { $0.isASCII && $0.isNumber }) { return true }

        // Password-like: 8–64 characters with letters and digits, using at least three of lower, upper,
        // digits and symbols. Code such as `items.reduce(0)` is not a password.
        guard (8...64).contains(s.count), s.contains(where: \.isLetter),
              s.contains(where: { $0.isASCII && $0.isNumber }),
              s.wholeMatch(of: #/[A-Za-z_][\w.]*\(.*\);?/#) == nil else { return false }
        let classes = [
            s.contains(where: { $0.isLowercase }),
            s.contains(where: { $0.isUppercase }),
            s.contains(where: { $0.isASCII && $0.isNumber }),
            s.contains(where: { !$0.isLetter && !$0.isNumber }),
        ].filter { $0 }.count
        return classes >= 3
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
}
