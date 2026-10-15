import CoreGraphics
import Foundation
import KireiCore

/// Lasttest mit erzeugten Einträgen statt echter Fotos.
///
/// Misst, was der Kern selbst kostet: Abgleich mit dem Index, Pakete der
/// Analyse, Gruppenbildung und Speicher. Die Bildanalyse ist ersetzt durch
/// eine schnelle Rechnung, deshalb sagt die Zeit nichts über Vision.
enum Last {
    static func run(count: Int) async -> Int32 {
        print("Lasttest mit \(Zahl.ganz(count)) erzeugten Einträgen")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kirei-last-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Auf der Festplatte wie in der App, nicht im Arbeitsspeicher.
            let index = try AssetIndex.onDisk(directory: directory)
            let source = SyntheticSource(count: count)
            let scanner = LibraryScanner(
                source: source,
                analyzer: SyntheticAnalyzer(),
                hasher: nil,
                index: index,
                adaptsToDeviceState: false
            )

            let first = try await scanner.scan { _ in }
            print("Erster Scan:")
            print("  Gruppen ähnlich: \(Zahl.ganz(first.groups(in: .similar).count)), Bildschirmfotos und Videos: \(Zahl.ganz(first.groups.count - first.groups(in: .similar).count))")
            if let metrics = first.metrics {
                Messwerte.drucken(metrics)
                if metrics.analyzedInThisRun > 0 {
                    let perPhoto = metrics.analysisSeconds / Double(metrics.analyzedInThisRun) * 1_000
                    print("  Aufwand des Kerns pro Foto ohne Vision: \(Zahl.komma(perPhoto, stellen: 2)) ms")
                }
            }

            let second = try await scanner.scan { _ in }
            print("Zweiter Scan ohne Änderungen:")
            if let metrics = second.metrics {
                Messwerte.drucken(metrics)
            }
            return 0
        } catch {
            print("Lasttest fehlgeschlagen: \(error.localizedDescription)")
            return 1
        }
    }
}

/// Messwerte eines Scans in Textform.
enum Messwerte {
    static func drucken(_ metrics: ScanMetrics) {
        print("  Erste Ergebnisse nach \(Zahl.komma(metrics.firstResultsSeconds, stellen: 1)) s (Ziel unter 10 s)")
        print("  Analyse: \(Zahl.ganz(metrics.analyzedInThisRun)) Fotos in \(Zahl.komma(metrics.analysisSeconds, stellen: 1)) s")
        print("  Scan gesamt: \(Zahl.komma(metrics.totalSeconds, stellen: 1)) s (Lesen \(Zahl.komma(metrics.readingSeconds, stellen: 1)), Index-Abgleich \(Zahl.komma(metrics.syncSeconds, stellen: 1)), Analyse \(Zahl.komma(metrics.analysisSeconds, stellen: 1)), Vergleichen \(Zahl.komma(metrics.comparingSeconds, stellen: 1)))")
        print("  Spitzen-Speicher: \(Zahl.ganz(Int(metrics.peakMemoryBytes / 1_000_000))) MB (Ziel unter 300 MB)")
    }
}

/// Erzeugte Mediathek: Serien aus drei Aufnahmen, einzelne Fotos,
/// Bildschirmfotos und Videos, über Monate verteilt.
struct SyntheticSource: PhotoSource {
    let count: Int
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    func access() -> LibraryAccess { .full }

    func requestAccess() async -> LibraryAccess { .full }

    func fetchRecords() async throws -> [AssetRecord] {
        (0..<count).map(Self.record(_:))
    }

    static func record(_ index: Int) -> AssetRecord {
        // Je zehn Einträge: drei Aufnahmen einer Serie, sieben einzelne.
        let block = index / 10
        let position = index % 10
        let offset = Double(block) * 3_600 + (position < 3 ? Double(position) * 5 : Double(position) * 300)
        let date = start.addingTimeInterval(offset)
        let isScreenshot = index % 25 == 7
        let isVideo = index % 50 == 9
        return AssetRecord(
            id: AssetID("synthetic-\(index)"),
            kind: isVideo ? .video : .photo,
            traits: isScreenshot ? .screenshot : [],
            creationDate: date,
            modificationDate: start,
            pixelWidth: isScreenshot ? 1179 : 4032,
            pixelHeight: isScreenshot ? 2556 : 3024,
            duration: isVideo ? 45 : 0
        )
    }

    /// Ein winziges Bild, dessen drei Pixel die Nummer des Eintrags tragen.
    func thumbnail(for id: AssetID, maxPixelSize: Int, mode: ThumbnailMode) async -> Thumbnail? {
        guard let index = Int(id.rawValue.dropFirst("synthetic-".count)) else { return nil }
        let bytes: [UInt8] = [UInt8((index >> 16) & 0xff), UInt8((index >> 8) & 0xff), UInt8(index & 0xff)]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: 3,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: 3,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { return nil }
        return Thumbnail(cgImage: image)
    }
}

/// Ersatz für Vision: liest die Nummer aus dem Bild und rechnet daraus einen
/// Merkmalsvektor mit 768 Werten. Serienbilder liegen nah beieinander.
struct SyntheticAnalyzer: ImageAnalyzer {
    let version = 1

    func analyze(_ thumbnail: Thumbnail) async throws -> ImageAnalysis {
        guard let data = thumbnail.cgImage.dataProvider?.data as Data?, data.count >= 3 else {
            return ImageAnalysis(featurePrint: nil, aestheticScore: nil, isUtility: false, sharpness: 0)
        }
        let index = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
        let block = index / 10
        let position = index % 10
        // Serie: gleiche Richtung, kleiner Unterschied. Einzelne: eigene Richtung.
        let seed = position < 3 ? block * 31 : block * 31 + position + 1_000_000
        var vector = Self.direction(seed: seed)
        if position < 3 {
            vector[position] += 0.05
        }
        return ImageAnalysis(
            featurePrint: FeaturePrint(vector: vector),
            aestheticScore: 0.2,
            isUtility: false,
            sharpness: 100 + Double(position)
        )
    }

    func analyzeFaces(_ thumbnail: Thumbnail) async throws -> FaceSummary {
        .none
    }

    static func direction(seed: Int) -> [Float] {
        var state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1
        var vector = [Float](repeating: 0, count: 768)
        var length: Float = 0
        for index in vector.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = Float(Int64(bitPattern: state >> 11) % 2_000) / 1_000 - 1
            vector[index] = value
            length += value * value
        }
        let scale = 1 / max(length.squareRoot(), 0.0001)
        return vector.map { $0 * scale }
    }
}
