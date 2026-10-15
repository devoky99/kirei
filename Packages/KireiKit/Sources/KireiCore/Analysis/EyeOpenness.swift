import CoreGraphics

/// Wie weit ein Auge geöffnet ist, aus den Umrisspunkten von Vision.
///
/// Verhältnis von Öffnung zu Breite des Auges. Offene Augen liegen meist
/// um 0,25 bis 0,4, geschlossene deutlich darunter. Gemessen entlang der
/// Linie zwischen den Augenwinkeln, damit ein schräg gehaltener Kopf nichts
/// verfälscht. Die Schwelle für „geschlossen“ wird im Prüfstand kalibriert.
public enum EyeOpenness {
    public static func ratio(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4 else { return nil }

        // Augenwinkel: die zwei Punkte mit dem größten Abstand.
        var cornerA = points[0]
        var cornerB = points[1]
        var width = 0.0
        for i in points.indices {
            for j in points.indices where j > i {
                let dx = Double(points[i].x - points[j].x)
                let dy = Double(points[i].y - points[j].y)
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance > width {
                    width = distance
                    cornerA = points[i]
                    cornerB = points[j]
                }
            }
        }
        guard width > 0 else { return nil }

        // Ausdehnung senkrecht zur Linie zwischen den Augenwinkeln.
        let directionX = Double(cornerB.x - cornerA.x) / width
        let directionY = Double(cornerB.y - cornerA.y) / width
        var above = 0.0
        var below = 0.0
        for point in points {
            let offsetX = Double(point.x - cornerA.x)
            let offsetY = Double(point.y - cornerA.y)
            let perpendicular = offsetY * directionX - offsetX * directionY
            above = max(above, perpendicular)
            below = min(below, perpendicular)
        }
        return (above - below) / width
    }
}
