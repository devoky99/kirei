import Foundation
import KireiCore

/// Prüft mit zwei erzeugten Bildern, ob Vision auf diesem Mac rechnet.
enum Selbsttest {
    static func run() async -> Int32 {
        print("Vision-Selbsttest")
        let info = ProcessInfo.processInfo
        let thermal = switch info.thermalState {
        case .nominal: "normal"
        case .fair: "leicht erhöht"
        case .serious: "hoch"
        case .critical: "kritisch"
        @unknown default: "unbekannt"
        }
        print("Temperatur:        \(thermal), Stromsparmodus \(info.isLowPowerModeEnabled ? "an" : "aus")")
        guard let checker = Testbilder.schachbrett(), let gradient = Testbilder.verlauf() else {
            print("Testbilder ließen sich nicht erzeugen.")
            return 1
        }

        let analyzer = VisionAnalyzer()
        do {
            let sharp = try await analyzer.analyze(Thumbnail(cgImage: checker))
            let soft = try await analyzer.analyze(Thumbnail(cgImage: gradient))
            let faces = try await analyzer.analyzeFaces(Thumbnail(cgImage: checker))

            let values = sharp.featurePrint?.values.count ?? 0
            print("Merkmalsvektor:    \(values) Werte")
            if let a = sharp.featurePrint, let b = soft.featurePrint {
                print("Abstand der Bilder: \(Zahl.komma(a.distance(to: b)))")
                print("Abstand zu sich:    \(Zahl.komma(a.distance(to: a)))")
            }
            print("Ästhetik-Score:    \(sharp.aestheticScore.map { Zahl.komma($0) } ?? "nicht verfügbar")")
            print("Gebrauchsbild:     \(sharp.isUtility ? "ja" : "nein")")
            print("Schärfe:           Schachbrett \(Zahl.ganz(Int(sharp.sharpness))), Verlauf \(Zahl.ganz(Int(soft.sharpness)))")
            print("Gesichter:         \(faces.faceCount)")

            let complete = sharp.featurePrint != nil && soft.featurePrint != nil && sharp.sharpness > soft.sharpness
            if complete && sharp.aestheticScore != nil {
                print("Ergebnis: Vision läuft vollständig.")
                return 0
            } else if complete {
                print("Ergebnis: Vision läuft, aber ohne Ästhetik-Score.")
                return 0
            } else {
                print("Ergebnis: Vision liefert unvollständige Werte.")
                return 1
            }
        } catch {
            print("Fehler: \(error.localizedDescription)")
            return 1
        }
    }
}
