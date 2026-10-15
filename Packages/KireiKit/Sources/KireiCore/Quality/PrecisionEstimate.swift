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

    public static func sweep(positives: [Double], negatives: [Double]) -> [Point] {
        let candidates = Array(Set(positives + negatives)).sorted()
        return candidates.map { threshold in
            let truePositives = positives.filter { $0 <= threshold }.count
            let falsePositives = negatives.filter { $0 <= threshold }.count
            return Point(
                threshold: threshold,
                truePositives: truePositives,
                falsePositives: falsePositives,
                recall: positives.isEmpty ? 0 : Double(truePositives) / Double(positives.count)
            )
        }
    }

    /// Größte Schwelle, deren Untergrenze das Ziel erreicht. Gibt es keine,
    /// weil zu wenig markiert ist, die größte Schwelle ohne falschen Vorschlag.
    ///
    /// Nur Werte markierter Positive kommen als Schwelle in Frage: eine
    /// Schwelle genau auf einem Negativ bringt einen Fehler und keinen Treffer.
    public static func recommend(positives: [Double], negatives: [Double], target: Double) -> Recommendation? {
        let positiveValues = Set(positives)
        let points = sweep(positives: positives, negatives: negatives)
            .filter { positiveValues.contains($0.threshold) }
        if let safe = points.last(where: { $0.estimate.lowerBound >= target }) {
            return Recommendation(point: safe, isStatisticallySafe: true)
        }
        if let clean = points.last(where: { $0.falsePositives == 0 }) {
            return Recommendation(point: clean, isStatisticallySafe: false)
        }
        return nil
    }

    public struct Recommendation: Sendable, Equatable {
        public let point: Point
        /// `false`: es gab keinen Fehler, aber zu wenige Markierungen für eine sichere Aussage.
        public let isStatisticallySafe: Bool
    }
}
