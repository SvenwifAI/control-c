<p align="center">
  <img src="docs/screenshot-compact.png" width="420" alt="Control+C popup with recent clipboard items">
</p>

<h1 align="center">Control+C</h1>

<p align="center">
  Your clipboard history, one shortcut away.<br>
  A small, native macOS app built with SwiftUI and Liquid Glass.
</p>

<p align="center">
  <a href="README.nl.md">Nederlands</a>
</p>

---

Press **⌘↩** anywhere and a compact popup appears at your mouse, showing what you copied recently. Pick an item and it's on your clipboard: press ⌘V to paste it. You don't have to open Spotlight or click an icon first, and the app needs no special permissions.

## Features

- **Instant:** opens at your mouse with no animation and no delay.
- **Search everything,** including the text inside screenshots. Copied images are read on your Mac with Apple Vision.
- **Sorted by kind:** text, links, images, files, code, colors and email addresses each get their own color, and you can filter on them. A small app icon shows where each item came from.
- **Keeps formatting and files:** bold text and links paste as they were copied (`⌥↩` copies plain text), and files copied in Finder paste back as real files.
- **Preview:** press Tab for a larger view with a full preview, source app and details.
- **Your shortcut:** pick any key combination in Settings.
- **Private:** nothing ever leaves your Mac, and secrets from password managers are never stored.
- **English and Dutch:** the app follows your Mac's language.

<p align="center">
  <img src="docs/screenshot-expanded.png" width="720" alt="Expanded view with preview pane">
</p>

## Install

Requires **macOS 26 (Tahoe)** or later and the Xcode Command Line Tools:

```bash
xcode-select --install
```

Then build and install:

```bash
git clone https://github.com/SvenwifAI/control-c.git
cd control-c
./build.sh
```

`build.sh` compiles the app from `Sources/`, installs it as `/Applications/ControlC.app` and starts it. Nothing is downloaded.

**No permissions needed:** Control+C doesn't ask for Accessibility, Screen Recording or anything else. It only reads and writes the clipboard, like any app can. Choosing an item puts it on your clipboard; you paste it with ⌘V.

**Settings:** choose *Settings…* from the clipboard icon in the menu bar, or press `⌘,` or the gear in the popup. You can set your shortcut, how many items to keep and for how long, apps to ignore, and whether Control+C starts at login.

## Keyboard

| Key | Action |
|---|---|
| `⌘↩` | Open or close the popup (this takes ⌘↩ away from other apps, such as *send* in Slack or Teams; pick another shortcut in Settings if that clashes) |
| Type | Search, including text in images |
| `↑` `↓` | Move the selection |
| `↩` or double-click | Copy and close, then paste with ⌘V |
| Single click | Copy and keep the popup open |
| `⌥↩` | Copy without formatting |
| `⌘1` … `⌘9` | Copy item 1 to 9 directly |
| `⌘←` `⌘→` | Filter by kind |
| `Tab` | Larger view with preview |
| `⌘⌫` | Delete item (also × on hover, or right-click) |
| `⌘Z` | Undo delete |
| `⇧⌘⌫` | Clear everything (asks first) |
| `⌘,` | Settings |
| `esc` | Close |

You can drag the popup by any empty spot.

## Privacy and security

- **Everything stays on your Mac.** The app makes no network connections.
- **Encrypted on disk.** Your history and images are stored with AES-256-GCM in `~/Library/Application Support/ControlC/`, each file bound to its name so files can't be swapped. The key is created on first launch and kept in your macOS Keychain, never in a file. Only your user account can read the folder, and it is excluded from Time Machine. If the Keychain refuses access, nothing is written at all and Settings tells you so.
- **Passwords and codes are recognized and never saved.** These stay in memory only, shown as `••••••••`, are not searchable, and disappear after 5 minutes:
  - 2FA codes, card numbers, and password-like text such as `Zomer2026!` or Apple's `xupjo4-gyzZyc-bavkif`
  - API keys and tokens (GitHub, GitLab, Anthropic, OpenAI, Stripe, Slack, AWS, Google and more), JWTs and private keys, also inside a longer text
  - config lines like `export API_KEY=…` or `Password: …`, and links with a password in them (`postgres://user:pass@host`)
  - screenshots whose text shows a key, token, labelled password or card number

  Pasting a secret back marks it as concealed and keeps it off Universal Clipboard, so other clipboard tools and devices skip it. You can turn recognition off in Settings.
- **Concealed copies are skipped** entirely: password managers such as 1Password mark what they copy as concealed or transient, and Control+C then keeps nothing of it.
- **Excluded apps:** nothing you copy in apps you exclude in Settings is stored, including a copy made right before switching apps. Excluding an app also removes what it already added.
- **Items expire after 7 days** without use, and at most 60 are kept (secrets don't count). Both are adjustable in Settings. Text over 1 MB and images over 20 MB or 50 megapixels are never stored. *Clear History* deletes every file and replaces the key, so old copies elsewhere can't be read either.
- **Hidden from screen sharing** by default: the popup asks macOS to be left out of screen sharing, recordings and screenshots. Most apps respect that; check yours before relying on it.
- **No special permissions.** The app doesn't use Accessibility, so it can't type into other apps or read their windows. It is built with the hardened runtime, so no other program can load code into it to borrow its Keychain key.
- **Heads-up:** recognizing secrets is a best guess. A word followed by a number (`Summer2026`), a password of only letters, a passphrase with spaces or dashes, and anything past the first 64 KB of a copy can slip through. Such an item is still encrypted on disk, and you can delete it with `⌘⌫`.
- **Only run a build you made yourself** from this source. A prebuilt `.app` from someone else can't be verified, yet it would see everything you copy.

## Fewer Keychain prompts after rebuilding (optional)

The Keychain gives the history key only to the app that created it, recognized by its code signature. Without a stable certificate, every `./build.sh` makes a new signature, so macOS asks once more whether Control+C may use its key. Create a code-signing certificate named **Control+C Signing** in Keychain Access (Certificate Assistant → Create a Certificate → type *Code Signing*). `build.sh` then uses it automatically and the question doesn't come back.

## Uninstall

```bash
pkill -x ControlC; rm -rf /Applications/ControlC.app ~/Library/Application\ Support/ControlC; security delete-generic-password -s com.svenvanrooijen.controlc -a history-key; defaults delete com.svenvanrooijen.controlc
```

Then remove Control+C from your Login Items.

## Project layout

| Path | What's there |
|---|---|
| `Sources/main.swift` | Clipboard store, popup UI, global shortcut, app delegate |
| `Sources/Settings.swift` | Preferences and the Settings window |
| `Sources/Demo.swift` | Sample data for screenshots (built only with `-D DEMO`) |
| `Scripts/make-icon.swift` | Renders `Resources/AppIcon.icns` |
| `Resources/*.lproj` | Translations (English is the source language) |
| `Scripts/screenshot.sh` | Regenerates the images in `docs/` from sample data |
| `build.sh` | Builds, signs, installs and launches the app |

## License

[MIT](LICENSE)
