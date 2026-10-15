import Foundation

/// Urteil über einen Vorschlag im Prüfmodus.
public enum ReviewVerdict: String, Codable, Sendable {
    case correct
    case wrong
}

/// Ein Vorschlag „ähnlich“ zum Prüfen: das behaltene und das vorgeschlagene Foto.
public struct ReviewPair: Identifiable, Sendable, Hashable {
    public let groupID: String
    /// Laufende Nummer der Gruppe, ab 1.
    public let groupNumber: Int
    public let keep: AssetID
    public let suggested: AssetID
    public let distance: Float?
    public let reasons: [SuggestionReason]

    public var id: String { ReviewLog.key(groupID: groupID, suggested: suggested) }

    /// Alle Vorschläge „ähnlich“ eines Scans, in der Reihenfolge der Gruppen.
    public static func pairs(from results: ScanResults) -> [ReviewPair] {
        var pairs: [ReviewPair] = []
        for (index, group) in results.groups(in: .similar).enumerated() {
            guard let keep = group.items.first(where: { $0.role == .keep }) else { continue }
            for item in group.suggested {
                pairs.append(ReviewPair(
                    groupID: group.id,
                    groupNumber: index + 1,
                    keep: keep.assetID,
                    suggested: item.assetID,
                    distance: item.distanceToKeep,
                    reasons: item.reasons
                ))
            }
        }
        return pairs
    }
}

/// Alle Urteile aus dem Prüfmodus. Bleibt lokal auf dem Gerät.
public struct ReviewLog: Codable, Sendable, Equatable {
    public private(set) var verdicts: [String: ReviewVerdict]

    public init(verdicts: [String: ReviewVerdict] = [:]) {
        self.verdicts = verdicts
    }

    /// Kennung eines Vorschlags. Gruppen-Kennungen sind über Scans hinweg stabil.
    public static func key(groupID: String, suggested: AssetID) -> String {
        groupID + "#" + suggested.rawValue
    }

    public subscript(pair: ReviewPair) -> ReviewVerdict? {
        get { verdicts[pair.id] }
        set { verdicts[pair.id] = newValue }
    }

    /// Trefferquote über die geprüften Vorschläge aus `pairs`.
    public func estimate(for pairs: [ReviewPair]) -> PrecisionEstimate {
        var correct = 0
        var total = 0
        for pair in pairs {
            switch verdicts[pair.id] {
            case .correct:
                correct += 1
                total += 1
            case .wrong:
                total += 1
            case nil:
                break
            }
        }
        return PrecisionEstimate(correct: correct, total: total)
    }

    /// Erster noch nicht geprüfter Vorschlag, sonst der letzte.
    public func firstOpenIndex(in pairs: [ReviewPair]) -> Int {
        pairs.firstIndex { verdicts[$0.id] == nil } ?? max(0, pairs.count - 1)
    }
}

/// Speichert die Urteile als kleine JSON-Datei in Kireis eigenem Ordner.
public struct ReviewStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "review.json")
    }

    public static func standard() throws -> ReviewStore {
        ReviewStore(directory: try KireiStorage.directory())
    }

    public func load() -> ReviewLog {
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? JSONDecoder().decode(ReviewLog.self, from: data)
        else { return ReviewLog() }
        return log
    }

    public func save(_ log: ReviewLog) throws {
        let data = try JSONEncoder().encode(log)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Export der Urteile als CSV, lesbar für `kirei-pruefstand auswerten`.
///
/// Enthält keine Kennungen und keine Bilder, nur Abstand, Gründe und Urteil.
/// Damit lassen sich die Schwellen einstellen, ohne Fotos weiterzugeben.
public enum ReviewExport {
    public static func csv(pairs: [ReviewPair], log: ReviewLog, metrics: ScanMetrics?, photoCount: Int) -> String {
        var lines: [String] = []
        if let metrics {
            lines.append("# Fotos: \(photoCount)")
            lines.append("# Erste Ergebnisse: \(format(metrics.firstResultsSeconds, digits: 1)) s")
            lines.append("# Analysiert in diesem Durchlauf: \(metrics.analyzedInThisRun) Fotos in \(format(metrics.analysisSeconds, digits: 1)) s")
            if let projected = metrics.projectedAnalysisSeconds(for: 20_000) {
                lines.append("# Hochgerechnet auf 20.000 Fotos: \(format(projected / 60, digits: 1)) min")
            }
            lines.append("# Spitzen-Speicher: \(metrics.peakMemoryBytes / 1_000_000) MB")
        }
        lines.append("gruppe;abstand;gruende;urteil")
        for pair in pairs {
            let verdict: String = switch log[pair] {
            case .correct: "richtig"
            case .wrong: "falsch"
            case nil: ""
            }
            lines.append([
                String(pair.groupNumber),
                pair.distance.map { format(Double($0), digits: 4) } ?? "",
                pair.reasons.map(\.code).joined(separator: ","),
                verdict,
            ].joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
