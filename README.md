# Kirei

Ein ruhiger Foto-Aufräumer für iPhone, iPad und Mac. Einmal kaufen, alles auf dem Gerät, nichts sammeln.

Kirei ist ein Arbeitstitel. Stand: Phase 1, der Analyse-Kern.

## Loslegen

Voraussetzung: Mac mit Xcode 26 oder neuer (iOS 18 und macOS 15 bleiben die Mindestversionen).

1. `Kirei.xcodeproj` öffnen.
2. `Config/Local.xcconfig.example` als `Config/Local.xcconfig` kopieren und die eigene Team-ID eintragen. Das kostenlose persönliche Team reicht für Simulator, eigene Geräte und den Mac.
3. Oben in Xcode als Ziel einen iPhone- oder iPad-Simulator oder „My Mac“ wählen und starten.

Nach der Erlaubnis analysiert die App die Mediathek auf dem Gerät und zeigt die Vorschläge je Kategorie, jedes Foto mit seiner Begründung. Das ist noch die Testoberfläche aus Phase 1, gelöscht wird nichts. Originale aus iCloud werden nie geladen.

## Testen

```sh
scripts/test-all.sh
```

Das Skript testet den Kern auf dem Mac und im iOS-Simulator und baut die App für beide Plattformen. Dasselbe läuft bei jedem Push auf GitHub.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/Shared` | Oberfläche für alle Geräte |
| `App/iOS`, `App/macOS` | nur, was sich je Gerät anders bedient |
| `App/Resources` | Assets, Texte (Deutsch, Englisch), Datenschutz-Manifest |
| `Config` | Einstellungen, Info.plist, Mac-Sandbox |
| `Packages/KireiKit` | `KireiCore` (Analyse und Entscheidungen, ohne Oberfläche), `KireiUI` (gemeinsame Bausteine) |
| `Packages/Pruefstand` | misst den Kern auf dem Mac mit Testbildern |
| `scripts` | Bauen und Testen für beide Plattformen, Anmerkungen im GitHub-Build |

## Prüfstand

Misst den Analyse-Kern auf dem Mac mit Testbildern statt der Mediathek. Testbilder bleiben lokal und gehören nicht in dieses öffentliche Repo.

```sh
swift run -c release --package-path Packages/Pruefstand kirei-pruefstand <Befehl>
```

| Befehl | Wozu |
| --- | --- |
| `selbsttest` | prüft, ob Vision auf diesem Mac rechnet |
| `messen <Ordner>` | Zeit pro Foto, hochgerechnet auf 20.000 Fotos |
| `kalibrieren <Ordner>` | schlägt Schwellen aus markierten Beispielen vor |
| `vorschlaege <Ordner>` | läuft wie die App und schreibt die Vorschläge „ähnlich“ in eine Prüfseite |
| `auswerten <Datei.csv>` | zählt die Urteile und prüft Prüfpunkt 1 |

**Ordner für `kalibrieren`:** Fotos einfach in diese Unterordner ziehen, keine Liste nötig.

```
Testdaten/
  aehnlich/<serie>/      Fotos, die als fast gleich gelten sollen
  verschieden/<serie>/   ähnliche Motive, die getrennt bleiben sollen
  unscharf/  scharf/
  augen_zu/  augen_offen/
```

**Prüfpunkt 1:** `vorschlaege` auf einen Export der eigenen Mediathek anwenden (in Fotos: Ablage, Exportieren, Unbearbeitetes Original), die Prüfseite im Browser öffnen, jeden Vorschlag mit R oder F bewerten, „Urteile speichern“ und die Datei mit `auswerten` prüfen. Bestanden bei mindestens 1.000 geprüften Vorschlägen und einer Untergrenze der Trefferquote von mindestens 98 %.

## Grundsätze

Kein Abo, keine Werbung, keine Tracking- oder Analyse-SDKs, kein Netz für den Scan, nichts wird ohne Prüfkorb gelöscht. Die vollständigen Regeln stehen in [CLAUDE.md](CLAUDE.md).
