import Foundation

/// Kennung eines Fotos oder Videos in der Mediathek.
///
/// Bei PhotoKit ist das der `localIdentifier`. Er gilt nur auf diesem Gerät,
/// deshalb bleibt der Index in Version 1.0 pro Gerät.
public struct AssetID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Grobe Art eines Eintrags.
public enum AssetKind: String, Sendable, Codable, CaseIterable {
    case photo
    case video
    case other
}

/// Merkmale, die PhotoKit ohne Bildanalyse liefert.
public struct AssetTraits: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Bildschirmfoto.
    public static let screenshot = AssetTraits(rawValue: 1 << 0)
    /// Live Photo.
    public static let livePhoto = AssetTraits(rawValue: 1 << 1)
    /// Teil einer Serie (Burst).
    public static let burst = AssetTraits(rawValue: 1 << 2)
}

/// Alles, was Kirei über einen Eintrag weiß, bevor ein Bild geladen wird.
public struct AssetRecord: Identifiable, Hashable, Sendable {
    public let id: AssetID
    public let kind: AssetKind
    public let traits: AssetTraits
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Dauer in Sekunden, bei Fotos 0.
    public let duration: TimeInterval
    public let isFavorite: Bool
    /// Wurde in Fotos bearbeitet.
    public let hasAdjustments: Bool
    public let burstIdentifier: String?

    public init(
        id: AssetID,
        kind: AssetKind,
        traits: AssetTraits = [],
        creationDate: Date? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: TimeInterval = 0,
        isFavorite: Bool = false,
        hasAdjustments: Bool = false,
        burstIdentifier: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.traits = traits
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.hasAdjustments = hasAdjustments
        self.burstIdentifier = burstIdentifier
    }

    public var isScreenshot: Bool { traits.contains(.screenshot) }
}
