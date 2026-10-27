# Control+C

Met Control+C zie je je klembordgeschiedenis meteen voor je. Druk op **⌘↩** (Command + Enter), waar je ook bent, en er verschijnt een klein menu onder je tekstcursor met wat je de afgelopen tijd hebt gekopieerd. Je hoeft geen Spotlight te openen of eerst op een icoontje te klikken.

## Installeren

Je hebt nodig: macOS 26 (Tahoe) of nieuwer, en de Command Line Tools van Xcode.

```bash
xcode-select --install
```

Haal daarna de repo op en bouw de app:

```bash
git clone <repo-url> Control-C
cd Control-C
./build.sh
```

`build.sh` bouwt de app uit de broncode in `Sources/main.swift`, zet hem in `/Applications/ControlC.app` en start hem. Er wordt niets gedownload.

**Automatisch plakken:** de eerste keer vraagt macOS om toegang via Systeeminstellingen → Privacy en beveiliging → **Toegankelijkheid**. Zet Control+C daar aan. Zonder die toegang wordt een item alleen gekopieerd en plak je zelf met ⌘V. De app opent dan ook bij je muis in plaats van bij je tekstcursor.

**Starten bij inloggen:** klik op het klembord-icoon in de menubalk en kies *Start bij inloggen*.

## Gebruik

| | |
|---|---|
| `⌘↩` | Popup openen of sluiten |
| Typen | Zoeken |
| `↑` `↓` | Item kiezen |
| `↩` of dubbelklik | Plakken in de app waar je was |
| `⇧↩` of één klik | Alleen kopiëren |
| `⌘1` … `⌘9` | Item 1 t/m 9 meteen plakken |
| `tab` of het pijltjesknopje | Grote weergave met voorbeeld |
| `⌘⌫`, × of rechtermuisklik | Item verwijderen |
| `⌘Z` | Verwijderen ongedaan maken |
| `⇧⌘⌫` | Alles wissen (vraagt eerst om bevestiging) |
| `esc` | Sluiten |

## Privacy en veiligheid

- **Alles blijft op je Mac.** De app maakt geen internetverbinding.
- **Wachtwoorden uit wachtwoordmanagers** (1Password, iCloud-sleutelhanger, Bitwarden en andere apps die hun kopieën als geheim markeren) worden niet opgeslagen.
- **Je geschiedenis staat in** `~/Library/Application Support/ControlC/`. Alleen jouw gebruikersaccount kan die map lezen en hij gaat niet mee in Time Machine-backups.
- **Items verlopen na 7 dagen.** Er worden hooguit 60 items bewaard. Teksten groter dan 1 MB en afbeeldingen groter dan 20 MB worden niet bewaard.
- **Let op:** wat je zonder wachtwoordmanager kopieert, bijvoorbeeld een wachtwoord uit een notitie of een 2FA-code, komt wel in de geschiedenis. Verwijder zo'n item met `⌘⌫`.
- De toestemming voor Toegankelijkheid gebruikt de app alleen om je tekstcursor te vinden en om ⌘V te versturen.
- **Gebruik alleen een versie die je zelf hebt gebouwd.** Neem geen kant-en-klare `.app` van iemand anders over: die kun je niet controleren en hij krijgt wel toegang tot je klembord en tot Toegankelijkheid.

## Sneltoets aanpassen

⌘↩ werkt hierdoor niet meer in andere apps, zoals Slack, Teams of Claude, waar je er normaal berichten mee verstuurt. Wil je een andere sneltoets, pas dan deze regel aan in `Sources/main.swift`:

```swift
hotKey = HotKey(keyCode: kVK_Return, modifiers: cmdKey) { ... }
```

Bijvoorbeeld `kVK_ANSI_V, modifiers: cmdKey | shiftKey` voor ⌘⇧V. Draai daarna `./build.sh` opnieuw.

## Toestemming na elke nieuwe versie (optioneel)

macOS koppelt de Toegankelijkheid-toestemming aan de handtekening van de app. Zonder eigen certificaat moet je die toestemming daarom na elke `./build.sh` opnieuw aanzetten. Maak je in Sleutelhangertoegang een eigen certificaat voor codeondertekening met de naam **Control+C Signing** (Certificaatassistent → Maak een certificaat aan → type *Codeondertekening*), dan gebruikt `build.sh` dat automatisch en blijft de toestemming geldig.

## Verwijderen

```bash
pkill -x ControlC; rm -rf /Applications/ControlC.app ~/Library/Application\ Support/ControlC
```

Haal Control+C daarna ook weg uit Toegankelijkheid en uit je inlogonderdelen.
