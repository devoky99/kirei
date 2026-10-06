/// Woher der Kern seine Fotos bekommt.
///
/// In der App liefert `PhotoKitSource` die echte Mediathek, im Prüfstand
/// liefert ein Ordner mit markierten Testbildern. Der Kern merkt keinen
/// Unterschied, deshalb lassen sich Vorschläge auf dem Mac messen.
public protocol PhotoSource: Sendable {
    /// Aktueller Stand der Berechtigung, ohne nachzufragen.
    func access() -> LibraryAccess

    /// Fragt nach der Berechtigung, falls noch nicht geschehen.
    func requestAccess() async -> LibraryAccess

    /// Alle Einträge mit Metadaten, neueste zuerst. Lädt keine Bilder.
    func fetchRecords() async throws -> [AssetRecord]

    /// Ein lokales Vorschaubild. Gibt `nil` zurück, wenn es nur in iCloud liegt.
    func thumbnail(for id: AssetID, maxPixelSize: Int) async -> Thumbnail?
}

/// Eine Quelle, die sagen kann, was sich seit dem letzten Scan geändert hat.
public protocol LibraryChangeTracker: Sendable {
    /// Merkzettel für den aktuellen Stand der Mediathek.
    func currentChangeToken() async throws -> ChangeToken

    /// Was sich seit dem Merkzettel geändert hat.
    func changes(since token: ChangeToken) async throws -> LibraryChangeResult
}
