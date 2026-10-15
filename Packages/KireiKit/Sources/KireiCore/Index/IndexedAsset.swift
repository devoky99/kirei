import Foundation
import SwiftData

/// Ein Eintrag im lokalen Index: was Kirei über ein Foto bereits ausgerechnet hat.
///
/// Bleibt im App-Container, wird nie synchronisiert und nie gesendet.
@Model
final class IndexedAsset {
    // Schnelle Abfragen nach offenen Analysen und nach Datum.
    #Index<IndexedAsset>([\.analysisVersion], [\.sortDate, \.assetID], [\.analysisUnavailable])

    @Attribute(.unique) var assetID: String
    /// Aufnahmedatum, ohne Datum `distantPast`. Für die Sortierung.
    var sortDate: Date
    var hasDate: Bool
    var modificationDate: Date?
    var isAnalyzable: Bool

    // Bildanalyse
    /// 0 heißt noch nicht analysiert.
    var analysisVersion: Int
    /// Kein lokales Vorschaubild, etwa nur in iCloud.
    var analysisUnavailable: Bool
    var featurePrintData: Data?
    var aestheticScore: Double?
    var isUtility: Bool
    var sharpness: Double

    // Gesichter, nur für Fotos in Gruppen
    var faceVersion: Int
    var faceCount: Int
    var minEyeOpenness: Double?
    var faceQuality: Double?

    // Prüfsumme des lokalen Originals, nur für Duplikat-Kandidaten
    var contentHash: Data?

    init(record: AssetRecord) {
        assetID = record.id.rawValue
        sortDate = record.creationDate ?? .distantPast
        hasDate = record.creationDate != nil
        modificationDate = record.modificationDate
        isAnalyzable = record.isAnalyzable
        analysisVersion = 0
        analysisUnavailable = false
        featurePrintData = nil
        aestheticScore = nil
        isUtility = false
        sharpness = 0
        faceVersion = 0
        faceCount = 0
        minEyeOpenness = nil
        faceQuality = nil
        contentHash = nil
    }

    /// Übernimmt geänderte Metadaten und verwirft alles Ausgerechnete.
    func reset(with record: AssetRecord) {
        sortDate = record.creationDate ?? .distantPast
        hasDate = record.creationDate != nil
        modificationDate = record.modificationDate
        isAnalyzable = record.isAnalyzable
        analysisVersion = 0
        analysisUnavailable = false
        featurePrintData = nil
        aestheticScore = nil
        isUtility = false
        sharpness = 0
        faceVersion = 0
        faceCount = 0
        minEyeOpenness = nil
        faceQuality = nil
        contentHash = nil
    }

    var analyzedPhoto: AnalyzedPhoto {
        AnalyzedPhoto(
            id: AssetID(assetID),
            date: hasDate ? sortDate : nil,
            featurePrint: featurePrintData.flatMap(FeaturePrint.init(data:)),
            aestheticScore: aestheticScore.map(Float.init),
            isUtility: isUtility,
            sharpness: sharpness
        )
    }
}
