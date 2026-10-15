import Foundation

/// Die Kategorien von Version 1.0, in der Reihenfolge der Anzeige.
public enum SuggestionCategory: String, Sendable, Hashable, CaseIterable, Codable {
    case exactDuplicates
    case similar
    case bursts
    case blurry
    case screenshots
    case screenRecordings
    case largeVideos
}

/// Behalten oder zum Löschen vorschlagen.
public enum SuggestionRole: Sendable, Hashable {
    case keep
    case remove
}

/// Warum ein Foto geschützt ist. Geschützte Fotos werden nie vorgeschlagen.
public enum ProtectionReason: Sendable, Hashable {
    case favorite
    case edited
    case inAlbum
}

/// Jeder Vorschlag nennt seinen Grund. Die Texte dazu liegen in der App.
public enum SuggestionReason: Sendable, Hashable {
    // Gründe zum Behalten
    case bestOfGroup
    case sharpest
    case eyesOpen
    case original
    case burstSelection
    case protected(ProtectionReason)

    // Gründe für einen Vorschlag
    case exactCopy
    case nearlyIdentical
    case lessSharp
    case eyesClosed
    case unselectedBurstFrame
    case blurry
    case screenshot(ageInDays: Int)
    case screenRecording(seconds: Int)
    case largeVideo(estimatedBytes: Int64)

    /// Feste Kennung ohne Sprache, für Export und Auswertung.
    public var code: String {
        switch self {
        case .bestOfGroup: "bestOfGroup"
        case .sharpest: "sharpest"
        case .eyesOpen: "eyesOpen"
        case .original: "original"
        case .burstSelection: "burstSelection"
        case .protected(.favorite): "protectedFavorite"
        case .protected(.edited): "protectedEdited"
        case .protected(.inAlbum): "protectedInAlbum"
        case .exactCopy: "exactCopy"
        case .nearlyIdentical: "nearlyIdentical"
        case .lessSharp: "lessSharp"
        case .eyesClosed: "eyesClosed"
        case .unselectedBurstFrame: "unselectedBurstFrame"
        case .blurry: "blurry"
        case .screenshot: "screenshot"
        case .screenRecording: "screenRecording"
        case .largeVideo: "largeVideo"
        }
    }
}

/// Ein Foto oder Video in einer Gruppe.
public struct SuggestionItem: Identifiable, Sendable, Hashable {
    public let assetID: AssetID
    public let role: SuggestionRole
    public let reasons: [SuggestionReason]
    /// Nur bestätigte exakte Duplikate sind vorausgewählt.
    public let isPreselected: Bool
    public let estimatedBytes: Int64
    /// Abstand der Merkmalsvektoren zum behaltenen Foto, nur bei „ähnlich“.
    public let distanceToKeep: Float?

    public var id: AssetID { assetID }

    public init(
        assetID: AssetID,
        role: SuggestionRole,
        reasons: [SuggestionReason],
        isPreselected: Bool = false,
        estimatedBytes: Int64 = 0,
        distanceToKeep: Float? = nil
    ) {
        self.assetID = assetID
        self.role = role
        self.reasons = reasons
        self.isPreselected = isPreselected && role == .remove
        self.estimatedBytes = estimatedBytes
        self.distanceToKeep = distanceToKeep
    }
}

/// Eine Gruppe von Vorschlägen, etwa eine Serie fast gleicher Fotos.
public struct SuggestionGroup: Identifiable, Sendable, Hashable {
    /// Stabil über Scans hinweg, damit „erledigt“ später gemerkt werden kann.
    public let id: String
    public let category: SuggestionCategory
    public let items: [SuggestionItem]

    public init(id: String, category: SuggestionCategory, items: [SuggestionItem]) {
        self.id = id
        self.category = category
        self.items = items
    }

    /// Die Einträge, die zum Löschen vorgeschlagen werden.
    public var suggested: [SuggestionItem] {
        items.filter { $0.role == .remove }
    }

    /// Geschätzter Platz, der frei würde. Immer als „etwa“ anzeigen.
    public var estimatedSavings: Int64 {
        suggested.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// Kennung aus Kategorie und Mitgliedern.
    static func makeID(_ category: SuggestionCategory, _ ids: [AssetID]) -> String {
        ([category.rawValue] + ids.map(\.rawValue).sorted()).joined(separator: "|")
    }
}
