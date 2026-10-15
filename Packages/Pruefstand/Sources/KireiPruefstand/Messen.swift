import Foundation
import KireiCore

/// Misst die Zeit pro Foto für Vorschaubild, Analyse und Gesichter.
///
/// Der Mac ist schneller als ein iPhone. Die Zahl ist eine erste Orientierung
/// für das Ziel „20.000 Fotos in unter 10 Minuten“, gemessen wird es vor der
/// Beta auf einem echten iPhone.
enum Messen {
    static func run(folder: URL) async -> Int32 {
        let source = FolderPhotoSource(folder: folder)
        let analyzer = VisionAnalyzer()
        let clock = ContinuousClock()

        let start = clock.now
        guard let records = try? await source.fetchRecords(), !records.isEmpty else {
            print("Keine Bilder gefunden in \(folder.path)")
            return 1
        }
        let reading = clock.now - start

        var thumbnailTime = Duration.zero
        var analysisTime = Duration.zero
        var faceTime = Duration.zero
        var measured = 0

        for record in records {
            let t0 = clock.now
            guard let thumbnail = await source.thumbnail(
                for: record.id,
                maxPixelSize: ScanPolicy.analysisThumbnailPixelSize,
                mode: .fit
            ) else { continue }
            let t1 = clock.now
            _ = try? await analyzer.analyze(thumbnail)
            let t2 = clock.now
            _ = try? await analyzer.analyzeFaces(thumbnail)
            let t3 = clock.now

            thumbnailTime += t1 - t0
            analysisTime += t2 - t1
            faceTime += t3 - t2
            measured += 1
        }

        guard measured > 0 else {
            print("Keines der Bilder ließ sich lesen.")
            return 1
        }

        func perPhoto(_ total: Duration) -> Double {
            total.inSeconds * 1000 / Double(measured)
        }

        let perPhotoSeconds = (thumbnailTime + analysisTime).inSeconds / Double(measured)
        let sequentialMinutes = perPhotoSeconds * 20_000 / 60
        let parallelMinutes = sequentialMinutes / 4

        print("Ordner:            \(folder.path)")
        print("Fotos gemessen:    \(Zahl.ganz(measured)) von \(Zahl.ganz(records.count))")
        print("Metadaten lesen:   \(Zahl.komma(reading.inSeconds)) s")
        print("Pro Foto:")
        print("  Vorschaubild     \(Zahl.komma(perPhoto(thumbnailTime), stellen: 1)) ms")
        print("  Analyse          \(Zahl.komma(perPhoto(analysisTime), stellen: 1)) ms")
        print("  Gesichter        \(Zahl.komma(perPhoto(faceTime), stellen: 1)) ms (nur für Fotos in Gruppen)")
        print("Hochgerechnet auf 20.000 Fotos ohne Gesichter:")
        print("  nacheinander     \(Zahl.komma(sequentialMinutes, stellen: 1)) min")
        print("  4 parallel       \(Zahl.komma(parallelMinutes, stellen: 1)) min (Mac), Ziel unter 10 min auf dem iPhone")
        return 0
    }
}

extension Duration {
    var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
