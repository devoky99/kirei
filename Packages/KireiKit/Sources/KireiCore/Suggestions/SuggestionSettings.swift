import Foundation

/// Schutzregeln: diese Fotos werden nie vorgeschlagen. Einzeln abschaltbar.
public struct ProtectionRules: Sendable, Equatable {
    public var favorites: Bool
    public var edited: Bool
    public var userAlbums: Bool

    public init(favorites: Bool = true, edited: Bool = true, userAlbums: Bool = true) {
        self.favorites = favorites
        self.edited = edited
        self.userAlbums = userAlbums
    }

    public static let `default` = ProtectionRules()

    public func reason(for record: AssetRecord) -> ProtectionReason? {
        if favorites && record.isFavorite { return .favorite }
        if edited && record.hasAdjustments { return .edited }
        if userAlbums && record.isInUserAlbum { return .inAlbum }
        return nil
    }
}

/// Schwellen für Vorschläge. Alle Startwerte sind vorsichtig gewählt und
/// werden im Prüfstand mit der Test-Mediathek kalibriert.
public struct SuggestionSettings: Sendable, Equatable {
    /// Höchster Abstand der Merkmalsvektoren für „fast gleich“.
    /// Vision Revision 2: ähnliche Bilder liegen meist unter 0,4 bis 0,6.
    public var similarDistance: Float = 0.30
    /// Längste Pause zwischen zwei Fotos derselben Gruppe.
    public var similarMaxGap: TimeInterval = 60
    /// Längste Dauer einer Gruppe vom ersten bis zum letzten Foto.
    public var similarMaxSpan: TimeInterval = 600
    /// Unter dieser Augenöffnung gelten Augen als geschlossen.
    public var eyesClosedOpenness: Double = 0.12
    /// „Unschärfer“, wenn die Schärfe unter diesem Anteil des behaltenen Fotos liegt.
    public var lessSharpFactor: Double = 0.6
    /// „Unscharf“ nur, wenn Ästhetik-Score und Schärfe beide niedrig sind.
    public var blurAestheticMax: Float = -0.4
    public var blurSharpnessMax: Double = 40
    /// Jüngere Bildschirmfotos werden noch gebraucht.
    public var screenshotMinAgeDays: Int = 30
    /// Ab hier gilt ein Video als groß (geschätzt).
    public var largeVideoMinBytes: Int64 = 50_000_000
    public var protection: ProtectionRules = .default

    public init() {}

    public static let `default` = SuggestionSettings()
}
