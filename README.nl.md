<p align="center"><img src="docs/preview.nl.png" width="860" alt="Control+C: ingeklapt, uitgeklapt en de belangrijkste functies"></p>

# Control+C

[English](README.md)

Met Control+C zie je je klembordgeschiedenis meteen voor je. Druk op **⌘↩** (Command + Enter), waar je ook bent, en er verschijnt een klein menu bij je muis met wat je de afgelopen tijd hebt gekopieerd. Kies een item en het staat op je klembord: plakken doe je met ⌘V. Je hoeft geen Spotlight te openen of eerst op een icoontje te klikken, en de app heeft geen speciale toestemmingen nodig.

## Installeren

Je hebt nodig: macOS 26 (Tahoe) of nieuwer, en de Command Line Tools van Xcode.

```bash
xcode-select --install
```

Haal daarna de repo op en bouw de app:

```bash
git clone https://github.com/SvenwifAI/control-c.git
cd control-c
./build.sh
```

`build.sh` bouwt de app uit de broncode in `Sources/`, zet hem in `/Applications/ControlC.app` en start hem. Er wordt niets gedownload.

**Geen toestemmingen nodig:** Control+C vraagt niet om Toegankelijkheid, schermopname of iets anders. Hij leest en schrijft alleen het klembord, zoals elke app dat kan. Kies je een item, dan staat het op je klembord en plak je het met ⌘V.

**Instellingen:** klik op het klembord-icoon in de menubalk en kies *Instellingen…*, of druk op `⌘,` of het tandwiel in de popup. Daar kies je je eigen sneltoets, hoeveel items hij bewaart en hoe lang, welke apps hij moet negeren, en of hij moet starten bij inloggen.

## Gebruik

| | |
|---|---|
| `⌘↩` | Popup openen of sluiten |
| Typen | Zoeken |
| `↑` `↓` | Item kiezen |
| `↩` of dubbelklik | Kopiëren en sluiten, daarna plakken met ⌘V |
| Eén klik | Kopiëren, popup blijft open |
| `⌥↩` | Kopiëren zonder opmaak |
| `⌘1` … `⌘9` | Item 1 t/m 9 meteen kopiëren |
| `⌘←` `⌘→` of de filterknoppen | Alleen tekst, links, afbeeldingen, code, kleuren of e-mailadressen |
| `tab` of het pijltjesknopje | Grote weergave met voorbeeld |
| `⌘⌫`, × of rechtermuisklik | Item verwijderen |
| `⌘Z` | Verwijderen ongedaan maken |
| `⇧⌘⌫` | Alles wissen (vraagt eerst om bevestiging) |
| `⌘,` | Instellingen |
| `esc` | Sluiten |

**Taal:** de app volgt de taal van je Mac: Nederlands als je Mac in het Nederlands staat, anders Engels.

**Opmaak en bestanden:** vetgedrukte tekst en links plak je terug zoals je ze kopieerde, en bestanden die je in Finder kopieert plak je terug als echt bestand. Bij elk item zie je met een klein app-icoon waar het vandaan komt.

**Zoeken in screenshots:** in gekopieerde afbeeldingen wordt de tekst herkend, zodat je daar ook in kunt zoeken. Met een rechtermuisklik op een afbeelding kopieer je die tekst. Dit gebeurt met Apple Vision op je eigen Mac. Uitzetten kan in Instellingen.

## Privacy en veiligheid

- **Alles blijft op je Mac.** De app maakt geen internetverbinding.
- **Versleuteld op schijf.** Je geschiedenis en afbeeldingen worden met AES-256-GCM opgeslagen in `~/Library/Application Support/ControlC/`, elk bestand gekoppeld aan zijn naam zodat bestanden niet verwisseld kunnen worden. De sleutel wordt bij de eerste start gemaakt en staat in je macOS-sleutelhanger, nooit in een bestand. Alleen jouw gebruikersaccount kan de map lezen en hij gaat niet mee in Time Machine. Weigert de sleutelhanger, dan wordt er niets weggeschreven en zie je dat in Instellingen.
- **Wachtwoorden en codes worden herkend en nooit bewaard.** Die staan alleen in het geheugen, worden getoond als `••••••••`, zijn niet doorzoekbaar en verdwijnen na 5 minuten:
  - 2FA-codes, kaartnummers en tekst die op een wachtwoord lijkt, zoals `Zomer2026!` of Apples `xupjo4-gyzZyc-bavkif`
  - API-sleutels en tokens (GitHub, GitLab, Anthropic, OpenAI, Stripe, Slack, AWS, Google en meer), JWT's en privésleutels, ook midden in een langere tekst
  - configuratieregels zoals `export API_KEY=…` of `Wachtwoord: …`, en links met een wachtwoord erin (`postgres://app:Hx7k2Lp9@db.example.com`)
  - screenshots waarop een sleutel, token, gelabeld wachtwoord of kaartnummer te lezen is

  Plak je een geheim terug, dan wordt het als geheim gemarkeerd en blijft het van het Universele klembord af, zodat andere klembordapps en apparaten het overslaan. Herkenning uitzetten kan in Instellingen.
- **Gemarkeerde kopieën worden helemaal overgeslagen:** wachtwoordmanagers zoals 1Password markeren wat ze kopiëren als geheim of tijdelijk, en Control+C bewaart daar dan niets van.
- **Uitgesloten apps:** wat je kopieert in apps die je in Instellingen uitsluit, wordt niet bewaard, ook niet als je vlak na het kopiëren van app wisselt. Een app uitsluiten haalt ook weg wat die app al had toegevoegd.
- **Items verlopen na 7 dagen** zonder gebruik, en er worden hooguit 60 bewaard (geheimen tellen niet mee). Beide pas je aan in Instellingen. Tekst groter dan 1 MB en afbeeldingen groter dan 20 MB of 50 megapixel worden niet bewaard. *Geschiedenis wissen* verwijdert alle bestanden en vervangt de sleutel, zodat oude kopieën elders ook onleesbaar worden.
- **Verborgen bij scherm delen** (standaard): de popup vraagt macOS om buiten scherm delen, opnames en screenshots te blijven. De meeste apps houden zich daaraan; controleer het in jouw app voordat je erop vertrouwt.
- **Geen speciale toestemmingen.** De app gebruikt geen Toegankelijkheid, en kan dus niet in andere apps typen of hun vensters uitlezen. Hij is gebouwd met de hardened runtime, zodat geen ander programma code in de app kan laden om de sleutel van je geschiedenis te lenen.
- **Let op:** het herkennen van geheimen blijft een inschatting. Een woord met een getal erachter (`Zomer2026`), een wachtwoord van alleen letters, een wachtzin met spaties of streepjes, en alles na de eerste 64 KB van een kopie kunnen erdoorheen glippen. Zo'n item staat dan nog steeds versleuteld op schijf, en je verwijdert het met `⌘⌫`.
- **Gebruik alleen een versie die je zelf hebt gebouwd.** Neem geen kant-en-klare `.app` van iemand anders over: die kun je niet controleren en hij ziet wel alles wat je kopieert.

## Sneltoets aanpassen

⌘↩ verstuurt ook berichten in apps als Slack, Teams en Claude, en Control+C neemt die sneltoets over. Kies in Instellingen een andere combinatie: klik op de sneltoets en druk de nieuwe in, bijvoorbeeld ⌘⇧V of ⌃⌥V. Combinaties die je Mac zelf nodig heeft (zoals ⌘V of ⌥ met een letter) worden geweigerd.

## Minder sleutelhanger-vragen na het bouwen (optioneel)

De sleutelhanger geeft de sleutel van je geschiedenis alleen aan de app die hem maakte, herkend aan de handtekening. Zonder eigen certificaat krijgt elke `./build.sh` een nieuwe handtekening, en vraagt macOS opnieuw of Control+C de sleutel mag gebruiken. Maak je in Sleutelhangertoegang een eigen certificaat voor codeondertekening met de naam **Control+C Signing** (Certificaatassistent → Maak een certificaat aan → type *Codeondertekening*), dan gebruikt `build.sh` dat automatisch en komt die vraag niet terug.

## Verwijderen

```bash
pkill -x ControlC; rm -rf /Applications/ControlC.app ~/Library/Application\ Support/ControlC; security delete-generic-password -s com.svenvanrooijen.controlc -a history-key; defaults delete com.svenvanrooijen.controlc
```

Haal Control+C daarna ook weg uit je inlogonderdelen.

## Licentie

[MIT](LICENSE)
