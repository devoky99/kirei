import Foundation

/// Trefferquote mit einer vorsichtigen Untergrenze.
///
/// Bei 980 richtigen von 1.000 Vorschlägen liegt die Quote bei 98 %, die
/// echte Quote kann aber noch bei 97 % liegen. Die Untergrenze (Wilson,
/// 95 % Sicherheit) sagt, wie schlecht es höchstens ist. Prüfpunkt 1 gilt
/// als bestanden, wenn sie über dem Ziel liegt.
public struct PrecisionEstimate: Sendable, Equatable {
    public let correct: Int
    public let total: Int

    public init(correct: Int, total: Int) {
        self.correct = correct
        self.total = total
    }

    public var precision: Double {
        total > 0 ? Double(correct) / Double(total) : 0
    }

    /// Untere Grenze des 95-%-Vertrauensbereichs nach Wilson.
    public var lowerBound: Double {
        guard total > 0 else { return 0 }
        let n = Double(total)
        let p = precision
        let z = 1.959964
        let z2 = z * z
        let center = p + z2 / (2 * n)
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
        return (center - margin) / (1 + z2 / n)
    }

    /// Prüfpunkt 1: genug Vorschläge geprüft und Untergrenze über dem Ziel.
    public func meets(target: Double, minimumCount: Int) -> Bool {
        total >= minimumCount && lowerBound >= target
    }
}

/// Findet die Schwelle, bis zu der Vorschläge noch verlässlich sind.
///
/// Erwartet Werte, bei denen „kleiner oder gleich Schwelle“ einen Vorschlag
/// auslöst, etwa Abstände zweier Fotos oder die Augenöffnung.
///
/// Nur eine Hilfe zum Einstellen. Ob Prüfpunkt 1 erreicht ist, zeigt erst die
/// Prüfung echter Vorschläge mit `PrecisionEstimate`.
public enum ThresholdCalibration {
    public struct Point: Sendable, Equatable {
        public let threshold: Double
        /// Richtige Vorschläge: markierte Positive unter der Schwelle.
        public let truePositives: Int
        /// Falsche Vorschläge: markierte Negative unter der Schwelle.
        public let falsePositives: Int
        /// Anteil der Positiven, der gefunden wird.
        public let recall: Double

        public var estimate: PrecisionEstimate {
            PrecisionEstimate(correct: truePositives, total: truePositives + falsePositives)
        }
    }

    public struct Recommendation: Sendable, Equatable {
        public let point: Point
        /// `false`: kein Fehler, aber zu wenige Beispiele für eine sichere Aussage.
        public let isStatisticallySafe: Bool
    }

    /// Alle sinnvollen Schwellen mit Treffern und Fehlern. Läuft über sortierte
    /// Listen, damit auch viele tausend Paare schnell gehen.
    public static func sweep(positives: [Double], negatives: [Double]) -> [Point] {
        let sortedPositives = positives.sorted()
        let sortedNegatives = negatives.sorted()
        let thresholds = Array(Set(positives + negatives)).sorted()

        var points: [Point] = []
        points.reserveCapacity(thresholds.count)
        var positiveIndex = 0
        var negativeIndex = 0
        for threshold in thresholds {
            while positiveIndex < sortedPositives.count && sortedPositives[positiveIndex] <= threshold {
                positiveIndex += 1
            }
            while negativeIndex < sortedNegatives.count && sortedNegatives[negativeIndex] <= threshold {
                negativeIndex += 1
            }
            points.append(Point(
                threshold: threshold,
                truePositives: positiveIndex,
                falsePositives: negativeIndex,
                recall: positives.isEmpty ? 0 : Double(positiveIndex) / Double(positives.count)
            ))
        }
        return points
    }

    /// Größte Schwelle, deren Untergrenze das Ziel erreicht. Gibt es keine,
    /// oder fehlen Beispiele, die größte Schwelle ohne falschen Vorschlag.
    ///
    /// Nur Werte markierter Positive kommen als Schwelle in Frage: eine
    /// Schwelle genau auf einem Negativ bringt einen Fehler und keinen Treffer.
    /// Als sicher gilt eine Empfehlung erst mit genug Positiven und Negativen,
    /// sonst fehlt der Gegenbeleg.
    public static func recommend(
        positives: [Double],
        negatives: [Double],
        target: Double,
        minimumEach: Int = 100
    ) -> Recommendation? {
        let positiveValues = Set(positives)
        let points = sweep(positives: positives, negatives: negatives)
            .filter { positiveValues.contains($0.threshold) }
        let enoughExamples = positives.count >= minimumEach && negatives.count >= minimumEach

        if enoughExamples, let safe = points.last(where: { $0.estimate.lowerBound >= target }) {
            return Recommendation(point: safe, isStatisticallySafe: true)
        }
        if let clean = points.last(where: { $0.falsePositives == 0 }) {
            return Recommendation(point: clean, isStatisticallySafe: false)
        }
        return nil
    }
}
