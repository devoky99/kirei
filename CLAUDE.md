# Kirei

Foto-Aufräumer für iPhone, iPad und Mac. Kirei ist ein Arbeitstitel.
Versprechen: einmal kaufen, alles auf dem Gerät, nichts sammeln, lieber ein Vorschlag zu wenig als einer zu viel.

## Grundsätze (nicht verhandelbar)

- Kein Abo, keine Werbung, keine Analyse-, Absturz- oder Werbe-SDKs. Datenschutzlabel „Keine Daten erfasst“.
- Kein Netz im Scan, keine Originale aus iCloud, nur lokale Vorschaubilder analysieren. Die Regel steht zentral in `ScanPolicy`.
- Nichts sofort löschen: Prüfkorb in der App, danach „Zuletzt gelöscht“ des Systems.
- Nur Fotos und Videos. Keine Kontakte, kein Kalender, kein „Speicher boosten“.
- Keine Dark Patterns: kein Countdown, keine künstlichen Rabatte, keine Angst-Bildschirme.
- Jeder Vorschlag nennt seinen Grund. Vorausgewählt sind nur exakte Duplikate.
- Weise von dir aus hin, wenn etwas gegen diese Grundsätze oder die App-Review-Richtlinien verstößt (besonders 2.3.1, 1.1.6, 3.1.2, 4.3(b), 5.1.1).

## Aufbau

- `App/` ist ein Multiplattform-Ziel für iOS und macOS (eine Bundle-ID, Universal Purchase).
  - `App/Shared/` gilt für alle Geräte.
  - `App/iOS/` und `App/macOS/` enthalten nur, was sich je Gerät anders bedient. Jede Datei dort steht komplett in `#if os(iOS)` bzw. `#if os(macOS)`.
  - Der Ordner ist mit Xcode synchronisiert: neue Dateien einfach anlegen, nicht in der Projektdatei eintragen.
- `Packages/KireiKit/`
  - `KireiCore`: entscheidet über Fotos und kennt kein UIKit, AppKit oder SwiftUI. Bildtyp ist `CGImage`, Fotos kommen über das Protokoll `PhotoSource`.
  - `KireiUI`: gemeinsame SwiftUI-Bausteine und Gestaltungswerte (`KireiTheme`).
- `Packages/Pruefstand/`: Kommandozeilen-Werkzeug für den Mac, misst den Kern mit Testbildern statt Mediathek.
- `Config/`: Einstellungen (`Kirei.xcconfig`), Info.plist-Ergänzungen, Mac-Berechtigungen. Die Mac-Sandbox hat absichtlich keine Netz-Berechtigung.

## Regeln für Code

- Alles, was über ein Foto entscheidet (gruppieren, bewerten, begründen, löschen), gehört in `KireiCore` und bekommt Tests.
- Eine Aktion, drei Wege: neue Aktionen als `KireiAction` in `App/Shared/AppActions.swift`, mit Geste oder Knopf, Tastenkürzel und VoiceOver-Beschriftung.
- Swift 6 mit strikter Nebenläufigkeitsprüfung. Keine Warnungen einführen.
- Keine Fremdbibliotheken ohne Rückfrage. Keine nicht dokumentierten APIs ohne Hinweis auf das Prüfrisiko.
- Datenschutz-Manifest (`App/Resources/PrivacyInfo.xcprivacy`) aktualisieren, sobald eine Schnittstelle mit Pflichtbegründung dazukommt.
- Testbilder und Test-Mediathek nie ins Repo. Das Repo ist öffentlich.

## Texte

- Quellsprache Englisch, Deutsch vollständig im String Catalog (`App/Resources/Localizable.xcstrings`), mit Pluralformen.
- Freundlich und knapp, nie alarmierend. Keine Gedankenstriche als Satzzeichen.

## Fertig heißt

Eine Aufgabe ist erst erledigt, wenn alles stimmt, auf beiden Plattformen:

1. `scripts/test-all.sh` ist grün (Kern-Tests auf Mac und iOS-Simulator, App für beide gebaut).
2. Neue Texte stehen im String Catalog auf Deutsch und Englisch.
3. Jede neue Aktion hat Geste, Tastenkürzel und VoiceOver-Beschriftung.
4. Größte Schriftstufe und dunkles Erscheinungsbild sind geprüft.
5. Kein Netz im Scan, keine Originale aus iCloud.
6. Keine neue Fremdbibliothek, keine undokumentierte Schnittstelle ohne Rückfrage.
7. Datenschutz-Manifest ist aktuell.
8. Änderungen an der Vorschlagslogik nur mit neuem Prüfstand-Lauf; die Trefferquote darf nicht sinken.

## Befehle

```sh
scripts/test-all.sh                                   # alles bauen und testen
swift test --package-path Packages/KireiKit           # nur Kern-Tests auf dem Mac
swift run --package-path Packages/Pruefstand kirei-pruefstand <Ordner>
```
