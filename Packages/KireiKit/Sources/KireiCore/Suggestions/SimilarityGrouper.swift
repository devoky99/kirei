import Foundation

/// Ein Foto, das für „ähnlich“ in Frage kommt: mit Datum und Merkmalsvektor.
public struct GroupingCandidate: Sendable, Equatable {
    public let photo: AnalyzedPhoto
    public let date: Date
    public let featurePrint: FeaturePrint

    public init?(photo: AnalyzedPhoto) {
        guard let date = photo.date, let featurePrint = photo.featurePrint else { return nil }
        self.photo = photo
        self.date = date
        self.featurePrint = featurePrint
    }

    public var id: AssetID { photo.id }
}

/// Gruppiert fast gleiche Fotos, die kurz nacheinander aufgenommen wurden.
///
/// Vorsichtig gebaut: ein Foto kommt nur in eine Gruppe, wenn es jedem
/// Mitglied ähnlich ist, nicht nur einem. So entstehen keine Ketten, in
/// denen das erste und das letzte Foto nichts mehr gemeinsam haben.
/// Verglichen wird nur innerhalb eines Zeitfensters, das spart Rechenzeit
/// und verhindert Gruppen aus verschiedenen Tagen.
///
/// Die Fotos müssen nach Aufnahmezeit aufsteigend kommen.
public struct SimilarityGrouper {
    public struct Cluster: Sendable, Equatable {
        public var members: [GroupingCandidate]
    }

    private let threshold: Float
    private let maxGap: TimeInterval
    private let maxSpan: TimeInterval
    private var open: [Cluster] = []
    private var closed: [Cluster] = []

    public init(settings: SuggestionSettings) {
        threshold = settings.similarDistance
        maxGap = settings.similarMaxGap
        maxSpan = settings.similarMaxSpan
    }

    public mutating func add(_ candidate: GroupingCandidate) {
        // Gruppen schließen, deren letztes Foto zu lange her ist.
        var stillOpen: [Cluster] = []
        for cluster in open {
            if let last = cluster.members.last, candidate.date.timeIntervalSince(last.date) > maxGap {
                close(cluster)
            } else {
                stillOpen.append(cluster)
            }
        }
        open = stillOpen

        // Die passendste offene Gruppe: der größte Abstand zu ihren Mitgliedern zählt.
        var bestIndex: Int?
        var bestDistance = Float.infinity
        for (index, cluster) in open.enumerated() {
            guard let first = cluster.members.first,
                  candidate.date.timeIntervalSince(first.date) <= maxSpan
            else { continue }
            var worst: Float = 0
            for member in cluster.members {
                worst = max(worst, member.featurePrint.distance(to: candidate.featurePrint))
                if worst > threshold { break }
            }
            if worst <= threshold && worst < bestDistance {
                bestDistance = worst
                bestIndex = index
            }
        }

        if let bestIndex {
            open[bestIndex].members.append(candidate)
        } else {
            open.append(Cluster(members: [candidate]))
        }
    }

    /// Fertige Gruppen mit mindestens zwei Fotos, seit dem letzten Aufruf.
    public mutating func drainClosed() -> [Cluster] {
        let result = closed
        closed = []
        return result
    }

    /// Schließt alle offenen Gruppen und gibt die restlichen fertigen zurück.
    public mutating func finish() -> [Cluster] {
        for cluster in open {
            close(cluster)
        }
        open = []
        return drainClosed()
    }

    private mutating func close(_ cluster: Cluster) {
        if cluster.members.count > 1 {
            closed.append(cluster)
        }
    }
}
