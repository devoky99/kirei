import Foundation

/// Merkzettel für den Stand der Mediathek (bei PhotoKit ein archiviertes
/// `PHPersistentChangeToken`). Damit analysiert der nächste Scan nur Neues.
public struct ChangeToken: Sendable, Codable, Equatable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// Neue, geänderte und gelöschte Einträge seit einem Merkzettel.
public struct LibraryChanges: Sendable, Equatable {
    public var inserted: Set<AssetID>
    public var updated: Set<AssetID>
    public var deleted: Set<AssetID>

    public init(inserted: Set<AssetID> = [], updated: Set<AssetID> = [], deleted: Set<AssetID> = []) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
    }

    public var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }

    /// Fasst zwei Änderungen zusammen. Was später gelöscht wurde, gilt als gelöscht.
    public mutating func merge(_ other: LibraryChanges) {
        inserted.formUnion(other.inserted)
        updated.formUnion(other.updated)
        deleted.formUnion(other.deleted)
        inserted.subtract(deleted)
        updated.subtract(deleted)
        updated.subtract(inserted)
    }
}

/// Ergebnis einer Änderungsabfrage.
public enum LibraryChangeResult: Sendable, Equatable {
    /// Nur diese Einträge müssen neu analysiert werden.
    case changes(LibraryChanges)
    /// Der Merkzettel ist abgelaufen oder unlesbar: einmal alles neu lesen.
    case fullScanRequired
}
