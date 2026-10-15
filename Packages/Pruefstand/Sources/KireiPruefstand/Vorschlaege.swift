import Foundation
import KireiCore

/// Eine Zeile zum Prüfen: ein vorgeschlagenes Foto und das behaltene.
struct Pruefzeile: Codable {
    let gruppe: Int
    let behalten: String
    let vorschlag: String
    let abstand: Float?
    let gruende: String
}

/// Läuft wie die App über einen Ordner und schreibt die Vorschläge „ähnlich“
/// zum Prüfen in eine HTML-Seite und eine CSV-Datei.
enum Vorschlaege {
    static func run(folder: URL) async -> Int32 {
        let source = FolderPhotoSource(folder: folder)
        print("Index wird angelegt …")
        let index: AssetIndex
        do {
            index = try AssetIndex.inMemory()
        } catch {
            print("Index ließ sich nicht anlegen: \(error.localizedDescription)")
            return 1
        }

        // Ohne Drosselung: der Prüfstand misst den Kern, nicht die Temperatur des Macs.
        let scanner = LibraryScanner(
            source: source,
            analyzer: VisionAnalyzer(),
            hasher: FileContentHasher(source: source),
            index: index,
            adaptsToDeviceState: false
        )
        let printer = ProgressPrinter()
        let results: ScanResults
        do {
            results = try await scanner.scan { update in
                await printer.show(update)
            }
        } catch {
            print("Scan fehlgeschlagen: \(error.localizedDescription)")
            return 1
        }

        print("")
        print("Fotos analysiert: \(Zahl.ganz(results.counts.processed - results.counts.unavailable)) von \(Zahl.ganz(results.counts.analyzable))")
        for category in SuggestionCategory.allCases {
            let groups = results.groups(in: category)
            guard !groups.isEmpty else { continue }
            let suggestions = groups.reduce(0) { $0 + $1.suggested.count }
            print("\(name(of: category)): \(Zahl.ganz(groups.count)) Gruppen, \(Zahl.ganz(suggestions)) Vorschläge")
        }

        let similar = results.groups(in: .similar)
        let ids = similar.flatMap { $0.items.map(\.assetID) }
        let prints = (try? await index.featurePrints(for: ids)) ?? [:]

        var rows: [Pruefzeile] = []
        for (number, group) in similar.enumerated() {
            guard let keep = group.items.first else { continue }
            for item in group.suggested {
                var distance: Float?
                if let keepPrint = prints[keep.assetID], let itemPrint = prints[item.assetID] {
                    distance = keepPrint.distance(to: itemPrint)
                }
                rows.append(Pruefzeile(
                    gruppe: number + 1,
                    behalten: keep.assetID.rawValue,
                    vorschlag: item.assetID.rawValue,
                    abstand: distance,
                    gruende: Gruende.text(item.reasons)
                ))
            }
        }

        guard !rows.isEmpty else {
            print("Keine Vorschläge „ähnlich“ gefunden. Mehr Serien in den Ordner legen?")
            return 0
        }

        let csvURL = folder.appending(path: "kirei-vorschlaege.csv")
        let htmlURL = folder.appending(path: "kirei-vorschlaege.html")
        do {
            try csv(rows).write(to: csvURL, atomically: true, encoding: .utf8)
            try Bericht.html(rows: rows).write(to: htmlURL, atomically: true, encoding: .utf8)
        } catch {
            print("Dateien ließen sich nicht schreiben: \(error.localizedDescription)")
            return 1
        }

        print("")
        print("\(Zahl.ganz(rows.count)) Vorschläge „ähnlich“ zum Prüfen:")
        print("  \(htmlURL.path)")
        print("Im Browser öffnen, jeden Vorschlag mit R (richtig) oder F (falsch) bewerten,")
        print("dann „Urteile speichern“ und die Datei auswerten:")
        print("  kirei-pruefstand auswerten ~/Downloads/kirei-urteile.csv")
        return 0
    }

    static func csv(_ rows: [Pruefzeile]) -> String {
        var lines = [CSV.zeile(["gruppe", "behalten", "vorschlag", "abstand", "gruende", "urteil"])]
        for row in rows {
            lines.append(CSV.zeile([
                String(row.gruppe),
                row.behalten,
                row.vorschlag,
                row.abstand.map { Zahl.komma($0, stellen: 3) } ?? "",
                row.gruende,
                "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func name(of category: SuggestionCategory) -> String {
        switch category {
        case .exactDuplicates: "Exakte Duplikate"
        case .similar: "Ähnliche Fotos"
        case .bursts: "Serien"
        case .blurry: "Unscharf"
        case .screenshots: "Bildschirmfotos"
        case .screenRecordings: "Bildschirmaufnahmen"
        case .largeVideos: "Große Videos"
        }
    }
}

/// Zeigt den Fortschritt in kurzen Zeilen.
actor ProgressPrinter {
    private var lastStage: ScanProgress.Stage?
    private var lastTenth = -1

    func show(_ update: ScanUpdate) {
        guard case .progress(let progress) = update else { return }
        if progress.stage != lastStage {
            lastStage = progress.stage
            lastTenth = -1
            switch progress.stage {
            case .reading: print("Ordner wird gelesen …")
            case .analyzing: print("Fotos werden analysiert …")
            case .comparing: print("Fotos werden verglichen …")
            case .faces: print("Gesichter werden geprüft …")
            case .paused: print("Pausiert, das Gerät meldet kritische Temperatur.")
            case .finished: print("Fertig.")
            }
        }
        if let fraction = progress.fraction {
            let tenth = Int(fraction * 10)
            if tenth > lastTenth {
                lastTenth = tenth
                print("  \(Zahl.ganz(progress.completed)) von \(Zahl.ganz(progress.total))")
            }
        }
    }
}
