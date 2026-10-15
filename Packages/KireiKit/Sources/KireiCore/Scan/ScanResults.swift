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

/// Messwerte eines Scans für Prüfpunkt 1.
public struct ScanMetrics: Sendable, Equatable {
    /// Bis die ersten Vorschläge da waren. Ziel: unter 10 Sekunden.
    public var firstResultsSeconds: Double
    /// Dauer der Bildanalyse in diesem Durchlauf.
    public var analysisSeconds: Double
    /// In diesem Durchlauf analysierte Fotos, ohne die bereits bekannten.
    public var analyzedInThisRun: Int
    public var totalSeconds: Double
    /// Höchster Speicherbedarf des Prozesses bisher. Ziel: unter 300 MB.
    public var peakMemoryBytes: Int64

    public init(
        firstResultsSeconds: Double,
        analysisSeconds: Double,
        analyzedInThisRun: Int,
        totalSeconds: Double,
        peakMemoryBytes: Int64
    ) {
        self.firstResultsSeconds = firstResultsSeconds
        self.analysisSeconds = analysisSeconds
        self.analyzedInThisRun = analyzedInThisRun
        self.totalSeconds = totalSeconds
        self.peakMemoryBytes = peakMemoryBytes
    }

    /// Analysezeit hochgerechnet auf eine Anzahl Fotos, `nil` ohne Analyse.
    public func projectedAnalysisSeconds(for photos: Int) -> Double? {
        guard analyzedInThisRun > 0 else { return nil }
        return analysisSeconds / Double(analyzedInThisRun) * Double(photos)
    }
}

/// Alle Vorschläge eines Scans.
public struct ScanResults: Sendable, Equatable {
    public var groups: [SuggestionGroup]
    public var summary: LibrarySummary
    public var counts: AnalysisCounts
    /// `false`, solange die Bildanalyse noch läuft.
    public var isComplete: Bool
    /// Nur im Endergebnis.
    public var metrics: ScanMetrics?

    public init(
        groups: [SuggestionGroup],
        summary: LibrarySummary,
        counts: AnalysisCounts,
        isComplete: Bool,
        metrics: ScanMetrics? = nil
    ) {
        self.groups = groups
        self.summary = summary
        self.counts = counts
        self.isComplete = isComplete
        self.metrics = metrics
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
