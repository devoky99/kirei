import Foundation
import KireiCore

/// Schlägt Schwellen aus markierten Beispielen vor.
///
/// Ordner-Aufbau (Fotos einfach hineinziehen, keine Liste nötig):
///   aehnlich/<serie>/      alle Fotos einer Serie gelten als fast gleich
///   verschieden/<serie>/   alle Fotos einer Serie sollen getrennt bleiben
///   unscharf/  scharf/
///   augen_zu/  augen_offen/
enum Kalibrieren {
    static let target = 0.98
    /// Große Serien ergeben sehr viele, voneinander abhängige Paare. Begrenzen.
    static let maximumSeriesSize = 30

    static func run(folder: URL) async -> Int32 {
        let source = FolderPhotoSource(folder: folder)
        let analyzer = VisionAnalyzer()
        let settings = SuggestionSettings.default
        var report: [String] = ["Kalibrierung für Kirei", "Ordner: \(folder.path)", ""]

        // Ähnlich und verschieden
        let positives = await pairDistances(in: folder.appending(path: "aehnlich"), source: source, analyzer: analyzer)
        let negatives = await pairDistances(in: folder.appending(path: "verschieden"), source: source, analyzer: analyzer)
        report += section(
            title: "Ähnlich (Abstand der Merkmalsvektoren)",
            positiveName: "ähnliche Paare",
            negativeName: "verschiedene Paare",
            positives: positives,
            negatives: negatives,
            current: Double(settings.similarDistance),
            settingName: "similarDistance"
        )

        // Unscharf und scharf
        let blurry = await analyses(in: folder.appending(path: "unscharf"), source: source, analyzer: analyzer)
        let sharp = await analyses(in: folder.appending(path: "scharf"), source: source, analyzer: analyzer)
        report += section(
            title: "Unscharf (Ästhetik-Score)",
            positiveName: "unscharfe Fotos",
            negativeName: "scharfe Fotos",
            positives: blurry.compactMap { $0.aestheticScore.map(Double.init) },
            negatives: sharp.compactMap { $0.aestheticScore.map(Double.init) },
            current: Double(settings.blurAestheticMax),
            settingName: "blurAestheticMax"
        )
        report += section(
            title: "Unscharf (eigene Schärfemessung)",
            positiveName: "unscharfe Fotos",
            negativeName: "scharfe Fotos",
            positives: blurry.map(\.sharpness),
            negatives: sharp.map(\.sharpness),
            current: settings.blurSharpnessMax,
            settingName: "blurSharpnessMax"
        )
        if !blurry.isEmpty || !sharp.isEmpty {
            let found = asPhotos(blurry).filter { SuggestionBuilder.isBlurry($0, settings: settings) }.count
            let wrong = asPhotos(sharp).filter { SuggestionBuilder.isBlurry($0, settings: settings) }.count
            report += [
                "Beide Regeln zusammen mit den aktuellen Werten:",
                "  erkannt \(found) von \(blurry.count) unscharfen, fälschlich \(wrong) von \(sharp.count) scharfen",
                "",
            ]
        }

        // Augen
        let closed = await eyeOpenness(in: folder.appending(path: "augen_zu"), source: source, analyzer: analyzer)
        let open = await eyeOpenness(in: folder.appending(path: "augen_offen"), source: source, analyzer: analyzer)
        report += section(
            title: "Augen geschlossen (Augenöffnung)",
            positiveName: "Fotos mit geschlossenen Augen",
            negativeName: "Fotos mit offenen Augen",
            positives: closed.values,
            negatives: open.values,
            current: settings.eyesClosedOpenness,
            settingName: "eyesClosedOpenness"
        )
        if closed.withoutFace + open.withoutFace > 0 {
            report += ["Ohne erkanntes Gesicht übersprungen: \(closed.withoutFace + open.withoutFace) Fotos", ""]
        }

        let text = report.joined(separator: "\n")
        print(text)
        let output = folder.appending(path: "kirei-kalibrierung.txt")
        try? text.write(to: output, atomically: true, encoding: .utf8)
        print("Gespeichert: \(output.path)")
        return positives.isEmpty && blurry.isEmpty && closed.values.isEmpty ? 1 : 0
    }

    // MARK: Messen

    /// Abstände aller Paare innerhalb jeder Serie (Unterordner).
    static func pairDistances(in directory: URL, source: FolderPhotoSource, analyzer: VisionAnalyzer) async -> [Double] {
        let series = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var distances: [Double] = []
        for folder in series.sorted(by: { $0.path < $1.path }) where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            var prints: [FeaturePrint] = []
            let files = source.imageFiles(in: folder)
            if files.count > maximumSeriesSize {
                print("Hinweis: \(source.relativePath(of: folder)) hat \(files.count) Fotos, gezählt werden die ersten \(maximumSeriesSize).")
            }
            for file in files.prefix(maximumSeriesSize) {
                let id = AssetID(source.relativePath(of: file))
                if let thumbnail = await source.thumbnail(for: id, maxPixelSize: ScanPolicy.analysisThumbnailPixelSize, mode: .fit),
                   let print = try? await analyzer.analyze(thumbnail).featurePrint {
                    prints.append(print)
                }
            }
            for i in prints.indices {
                for j in prints.indices where j > i {
                    distances.append(Double(prints[i].distance(to: prints[j])))
                }
            }
        }
        return distances
    }

    static func analyses(in directory: URL, source: FolderPhotoSource, analyzer: VisionAnalyzer) async -> [ImageAnalysis] {
        var result: [ImageAnalysis] = []
        for file in source.imageFiles(in: directory) {
            let id = AssetID(source.relativePath(of: file))
            if let thumbnail = await source.thumbnail(for: id, maxPixelSize: ScanPolicy.analysisThumbnailPixelSize, mode: .fit),
               let analysis = try? await analyzer.analyze(thumbnail) {
                result.append(analysis)
            }
        }
        return result
    }

    static func eyeOpenness(in directory: URL, source: FolderPhotoSource, analyzer: VisionAnalyzer) async -> (values: [Double], withoutFace: Int) {
        var values: [Double] = []
        var withoutFace = 0
        for file in source.imageFiles(in: directory) {
            let id = AssetID(source.relativePath(of: file))
            guard let thumbnail = await source.thumbnail(for: id, maxPixelSize: ScanPolicy.analysisThumbnailPixelSize, mode: .fit),
                  let faces = try? await analyzer.analyzeFaces(thumbnail),
                  let openness = faces.minEyeOpenness
            else {
                withoutFace += 1
                continue
            }
            values.append(openness)
        }
        return (values, withoutFace)
    }

    static func asPhotos(_ list: [ImageAnalysis]) -> [AnalyzedPhoto] {
        list.map {
            AnalyzedPhoto(
                id: AssetID("x"),
                date: nil,
                featurePrint: nil,
                aestheticScore: $0.aestheticScore,
                isUtility: $0.isUtility,
                sharpness: $0.sharpness
            )
        }
    }

    // MARK: Bericht

    static func section(
        title: String,
        positiveName: String,
        negativeName: String,
        positives: [Double],
        negatives: [Double],
        current: Double,
        settingName: String
    ) -> [String] {
        var lines = [title, String(repeating: "-", count: title.count)]
        guard !positives.isEmpty else {
            return lines + ["Keine \(positiveName) markiert, übersprungen.", ""]
        }
        lines.append("\(positiveName.capitalizedFirst): \(positives.count), \(spread(positives))")
        lines.append("\(negativeName.capitalizedFirst): \(negatives.count), \(spread(negatives))")

        let truePositives = positives.filter { $0 <= current }.count
        let falsePositives = negatives.filter { $0 <= current }.count
        let estimate = PrecisionEstimate(correct: truePositives, total: truePositives + falsePositives)
        lines.append("Aktuell \(settingName) = \(Zahl.komma(current, stellen: 3)): \(truePositives) Treffer, \(falsePositives) Fehler, Trefferquote \(Zahl.prozent(estimate.precision)), Untergrenze \(Zahl.prozent(estimate.lowerBound))")

        if let recommendation = ThresholdCalibration.recommend(positives: positives, negatives: negatives, target: target) {
            let point = recommendation.point
            lines.append("Empfehlung \(settingName) = \(Zahl.komma(point.threshold, stellen: 3)): findet \(Zahl.prozent(point.recall)) der \(positiveName), \(point.falsePositives) Fehler, Untergrenze \(Zahl.prozent(point.estimate.lowerBound))")
            if !recommendation.isStatisticallySafe {
                lines.append("  Ohne Fehler, aber noch zu wenige Beispiele für eine sichere Aussage (mindestens 100 je Seite, Ziel: Untergrenze \(Zahl.prozent(target))).")
            }
        } else {
            lines.append("Keine Schwelle ohne Fehler gefunden. Mehr Beispiele markieren oder Markierungen prüfen.")
        }
        lines.append("")
        return lines
    }

    static func spread(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "keine Werte" }
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        return "von \(Zahl.komma(sorted[0], stellen: 3)) über \(Zahl.komma(median, stellen: 3)) bis \(Zahl.komma(sorted[sorted.count - 1], stellen: 3))"
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
