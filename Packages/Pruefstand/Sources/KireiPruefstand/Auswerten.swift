import Foundation
import KireiCore

/// Zählt die Urteile aus der Prüfseite und prüft Prüfpunkt 1.
enum Auswerten {
    static let target = 0.98
    static let minimumCount = 1_000

    static let correctWords: Set<String> = ["richtig", "r", "ja", "j", "ok", "1"]
    static let wrongWords: Set<String> = ["falsch", "f", "nein", "n", "0"]

    static func run(file: URL) -> Int32 {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            print("Datei nicht lesbar: \(file.path)")
            return 66
        }
        let rows = CSV.lesen(text)
        guard let header = rows.first,
              let column = header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "urteil" })
        else {
            print("Die Spalte „urteil“ fehlt.")
            return 65
        }

        var correct = 0
        var wrong = 0
        var open = 0
        for row in rows.dropFirst() {
            let value = column < row.count ? row[column].trimmingCharacters(in: .whitespaces).lowercased() : ""
            if correctWords.contains(value) {
                correct += 1
            } else if wrongWords.contains(value) {
                wrong += 1
            } else {
                open += 1
            }
        }

        let estimate = PrecisionEstimate(correct: correct, total: correct + wrong)
        print("Geprüft:      \(Zahl.ganz(estimate.total)) (\(Zahl.ganz(correct)) richtig, \(Zahl.ganz(wrong)) falsch)")
        print("Offen:        \(Zahl.ganz(open))")
        guard estimate.total > 0 else {
            print("Noch keine Urteile.")
            return 2
        }
        print("Trefferquote: \(Zahl.prozent(estimate.precision))")
        print("Untergrenze:  \(Zahl.prozent(estimate.lowerBound)) (mit 95 % Sicherheit mindestens so gut)")
        print("")

        if estimate.meets(target: target, minimumCount: minimumCount) {
            print("Prüfpunkt 1 bestanden: mindestens \(Zahl.ganz(minimumCount)) Vorschläge geprüft, Untergrenze über \(Zahl.prozent(target)).")
            return 0
        }
        if estimate.total < minimumCount {
            print("Prüfpunkt 1 noch offen: \(Zahl.ganz(minimumCount - estimate.total)) Vorschläge fehlen bis \(Zahl.ganz(minimumCount)).")
        }
        if estimate.lowerBound < target {
            print("Die Untergrenze liegt unter \(Zahl.prozent(target)). Bei zu vielen Fehlern die Schwelle „similarDistance“ senken und neu prüfen.")
        }
        return 2
    }
}
