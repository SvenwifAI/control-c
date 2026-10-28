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

Press **⌘↩** anywhere and a compact popup appears right under your text cursor, showing what you copied recently. Pick an item and it pastes straight into the app you were typing in. You don't have to open Spotlight or click an icon first.

## Features

- **Instant:** opens at your text cursor with no animation and no delay.
- **Search everything,** including the text inside screenshots. Copied images are read on your Mac with Apple Vision.
- **Sorted by kind:** text, links, images, files, code, colors and email addresses each get their own color, and you can filter on them. A small app icon shows where each item came from.
- **Keeps formatting and files:** bold text and links paste as they were copied (`⌥↩` pastes plain text), and files copied in Finder paste back as real files.
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

**Pasting for you:** the first time, macOS asks for access under System Settings → Privacy & Security → **Accessibility**. Turn Control+C on there. Without it, choosing an item only copies it, so you paste it yourself with ⌘V. The popup then also opens at your mouse instead of your text cursor.

**Settings:** choose *Settings…* from the clipboard icon in the menu bar, or press `⌘,` or the gear in the popup. You can set your shortcut, how many items to keep and for how long, apps to ignore, and whether Control+C starts at login.

## Keyboard

| Key | Action |
|---|---|
| `⌘↩` | Open or close the popup |
| Type | Search, including text in images |
| `↑` `↓` | Move the selection |
| `↩` or double-click | Paste into the app you were in |
| `⇧↩` or single click | Copy only |
| `⌥↩` | Paste without formatting |
| `⌘1` … `⌘9` | Paste item 1 to 9 directly |
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
- **Password manager secrets are skipped.** That covers 1Password, iCloud Keychain, Bitwarden and other apps that mark what they copy as concealed.
- **Your history lives in** `~/Library/Application Support/ControlC/`. Only your user account can read that folder, and it is excluded from Time Machine.
- **Items expire after 7 days** without use, and at most 60 are kept. Both are adjustable in Settings. Text over 1 MB and images over 20 MB are never stored.
- **Excluded apps:** nothing you copy in apps you exclude in Settings is ever stored.
- **Heads-up:** text you copy from somewhere other than a password manager, such as a password in a note or a 2FA code, *is* kept. Delete it with `⌘⌫`.
- Accessibility access is used only to find your text cursor and to send ⌘V.
- **Only run a build you made yourself** from this source. A prebuilt `.app` from someone else can't be verified, yet it would get access to your clipboard and to Accessibility.

## Keep Accessibility access across rebuilds (optional)

macOS ties the Accessibility permission to the app's code signature. Without a stable certificate, you have to turn the permission back on after every `./build.sh`. Create a code-signing certificate named **Control+C Signing** in Keychain Access (Certificate Assistant → Create a Certificate → type *Code Signing*). `build.sh` then uses it automatically and the permission sticks.

## Uninstall

```bash
pkill -x ControlC; rm -rf /Applications/ControlC.app ~/Library/Application\ Support/ControlC
```

Then remove Control+C from Accessibility and from your Login Items.

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
