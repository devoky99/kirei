import Foundation

/// Fortschritt eines Scans für die Anzeige.
public struct ScanProgress: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        /// Metadaten lesen.
        case reading
        /// Bildanalyse.
        case analyzing
        /// Gruppen bilden.
        case comparing
        /// Gesichter in Gruppen prüfen.
        case faces
        /// Pause, bis das Gerät abgekühlt ist.
        case paused
        case finished
    }

    public var stage: Stage
    public var completed: Int
    public var total: Int

    public init(stage: Stage, completed: Int = 0, total: Int = 0) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }

    /// 0 bis 1, `nil` wenn unbestimmt.
    public var fraction: Double? {
        total > 0 ? min(1, Double(completed) / Double(total)) : nil
    }
}

/// Alle Vorschläge eines Scans.
public struct ScanResults: Sendable, Equatable {
    public var groups: [SuggestionGroup]
    public var summary: LibrarySummary
    public var counts: AnalysisCounts
    /// `false`, solange die Bildanalyse noch läuft.
    public var isComplete: Bool

    public init(groups: [SuggestionGroup], summary: LibrarySummary, counts: AnalysisCounts, isComplete: Bool) {
        self.groups = groups
        self.summary = summary
        self.counts = counts
        self.isComplete = isComplete
    }

    public static let empty = ScanResults(
        groups: [],
        summary: .empty,
        counts: AnalysisCounts(analyzable: 0, processed: 0, unavailable: 0),
        isComplete: false
    )

    public func groups(in category: SuggestionCategory) -> [SuggestionGroup] {
        groups.filter { $0.category == category }
    }
}

/// Was der Scanner unterwegs meldet.
public enum ScanUpdate: Sendable {
    case progress(ScanProgress)
    /// Alle Einträge der Mediathek, einmal pro Scan.
    case records([AssetRecord])
    /// Zwischenstand oder Endergebnis.
    case results(ScanResults)
}
