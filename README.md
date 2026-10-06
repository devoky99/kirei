# Kirei

Ein ruhiger Foto-Aufräumer für iPhone, iPad und Mac. Einmal kaufen, alles auf dem Gerät, nichts sammeln.

Kirei ist ein Arbeitstitel. Stand: Phase 0, das Gerüst.

## Loslegen

Voraussetzung: Mac mit Xcode 16 oder neuer.

1. `Kirei.xcodeproj` öffnen.
2. `Config/Local.xcconfig.example` als `Config/Local.xcconfig` kopieren und die eigene Team-ID eintragen. Das kostenlose persönliche Team reicht für Simulator, eigene Geräte und den Mac.
3. Oben in Xcode als Ziel einen iPhone- oder iPad-Simulator oder „My Mac“ wählen und starten.

Nach der Erlaubnis zeigt die App ein Raster aller lokal vorhandenen Vorschaubilder. Originale aus iCloud werden nie geladen.

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

## Prüfstand

```sh
swift run --package-path Packages/Pruefstand kirei-pruefstand ~/Pfad/zu/Testbildern
```

Testbilder bleiben lokal und gehören nicht in dieses öffentliche Repo.

## Grundsätze

Kein Abo, keine Werbung, keine Tracking- oder Analyse-SDKs, kein Netz für den Scan, nichts wird ohne Prüfkorb gelöscht. Die vollständigen Regeln stehen in [CLAUDE.md](CLAUDE.md).
