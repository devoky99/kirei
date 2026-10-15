import Foundation

/// Kennung eines Fotos oder Videos in der Mediathek.
///
/// Bei PhotoKit ist das der `localIdentifier`. Er gilt nur auf diesem Gerät,
/// deshalb bleibt der Index in Version 1.0 pro Gerät.
public struct AssetID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: AssetID, rhs: AssetID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
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
    /// Gehört zu einer Serie (Burst).
    public static let burst = AssetTraits(rawValue: 1 << 2)
    /// Bildschirmaufnahme (Video).
    public static let screenRecording = AssetTraits(rawValue: 1 << 3)
    /// Das Bild, das Fotos für eine Serie anzeigt.
    public static let burstRepresentative = AssetTraits(rawValue: 1 << 4)
    /// In der Serie vom Menschen ausgewählt.
    public static let burstUserPick = AssetTraits(rawValue: 1 << 5)
    /// In der Serie von der Kamera als gut markiert.
    public static let burstAutoPick = AssetTraits(rawValue: 1 << 6)
}

/// Alles, was Kirei über einen Eintrag weiß, bevor ein Bild geladen wird.
public struct AssetRecord: Identifiable, Hashable, Sendable {
    public let id: AssetID
    public let kind: AssetKind
    public let traits: AssetTraits
    public let creationDate: Date?
    /// Ändert sich bei jeder Bearbeitung. Dann wird neu analysiert.
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Dauer in Sekunden, bei Fotos 0.
    public let duration: TimeInterval
    public let isFavorite: Bool
    /// Wurde in Fotos bearbeitet.
    public let hasAdjustments: Bool
    /// Liegt in mindestens einem eigenen Album.
    public let isInUserAlbum: Bool
    public let burstIdentifier: String?

    public init(
        id: AssetID,
        kind: AssetKind,
        traits: AssetTraits = [],
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: TimeInterval = 0,
        isFavorite: Bool = false,
        hasAdjustments: Bool = false,
        isInUserAlbum: Bool = false,
        burstIdentifier: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.traits = traits
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.hasAdjustments = hasAdjustments
        self.isInUserAlbum = isInUserAlbum
        self.burstIdentifier = burstIdentifier
    }

    public var isScreenshot: Bool { traits.contains(.screenshot) }

    public var isScreenRecording: Bool { traits.contains(.screenRecording) }

    /// Ein Bild einer Serie, das Fotos nicht einzeln zeigt.
    public var isHiddenBurstFrame: Bool {
        burstIdentifier != nil
            && !traits.contains(.burstRepresentative)
            && !traits.contains(.burstUserPick)
    }

    /// Erscheint in Fotos als eigenes Bild.
    public var isVisibleInLibrary: Bool { !isHiddenBurstFrame }

    /// Bekommt eine Bildanalyse: Fotos ohne Bildschirmfotos und ohne verborgene Serienbilder.
    public var isAnalyzable: Bool {
        kind == .photo && !isScreenshot && !isHiddenBurstFrame
    }
}
