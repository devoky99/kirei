import Foundation

/// Ergebnis der Bildanalyse für ein Foto.
public struct ImageAnalysis: Sendable, Equatable {
    public var featurePrint: FeaturePrint?
    /// Ästhetik-Score von Vision, -1 bis 1. Höher wirkt gelungener.
    public var aestheticScore: Float?
    /// Gebrauchsbild wie Beleg, Dokument oder Whiteboard.
    public var isUtility: Bool
    /// Eigene Schärfemessung, siehe `SharpnessMeter`.
    public var sharpness: Double

    public init(featurePrint: FeaturePrint?, aestheticScore: Float?, isUtility: Bool, sharpness: Double) {
        self.featurePrint = featurePrint
        self.aestheticScore = aestheticScore
        self.isUtility = isUtility
        self.sharpness = sharpness
    }
}

/// Gesichter auf einem Foto, nur für Fotos in Gruppen berechnet.
public struct FaceSummary: Sendable, Equatable {
    public var faceCount: Int
    /// Kleinste Augenöffnung aller Gesichter, siehe `EyeOpenness`. `nil` ohne Gesicht.
    public var minEyeOpenness: Double?
    /// Mittlere Gesichtsqualität von Vision, 0 bis 1.
    public var meanCaptureQuality: Double?

    public init(faceCount: Int, minEyeOpenness: Double?, meanCaptureQuality: Double?) {
        self.faceCount = faceCount
        self.minEyeOpenness = minEyeOpenness
        self.meanCaptureQuality = meanCaptureQuality
    }

    public static let none = FaceSummary(faceCount: 0, minEyeOpenness: nil, meanCaptureQuality: nil)
}

/// Rechnet Merkmale aus einem Vorschaubild. In der App ist das `VisionAnalyzer`.
public protocol ImageAnalyzer: Sendable {
    /// Steigt, wenn sich die Analyse ändert. Dann wird alles neu berechnet.
    var version: Int { get }

    func analyze(_ thumbnail: Thumbnail) async throws -> ImageAnalysis

    func analyzeFaces(_ thumbnail: Thumbnail) async throws -> FaceSummary
}

/// Ein analysiertes Foto, wie es der Index für Gruppen und Bewertung liefert.
public struct AnalyzedPhoto: Sendable, Equatable {
    public let id: AssetID
    public let date: Date?
    public let featurePrint: FeaturePrint?
    public let aestheticScore: Float?
    public let isUtility: Bool
    public let sharpness: Double

    public init(
        id: AssetID,
        date: Date?,
        featurePrint: FeaturePrint?,
        aestheticScore: Float?,
        isUtility: Bool,
        sharpness: Double
    ) {
        self.id = id
        self.date = date
        self.featurePrint = featurePrint
        self.aestheticScore = aestheticScore
        self.isUtility = isUtility
        self.sharpness = sharpness
    }
}
