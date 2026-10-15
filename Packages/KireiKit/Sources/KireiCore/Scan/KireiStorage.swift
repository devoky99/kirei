import Foundation

/// Der Ordner für Kireis eigene Daten: Index und Scan-Stand.
///
/// Liegt in „Application Support/Kirei“, auf dem Mac im Sandbox-Container.
/// Vom Backup ausgenommen, weil sich alles neu berechnen lässt. So landet
/// nichts davon in iCloud-Backups oder Time Machine.
public enum KireiStorage {
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory = base.appending(path: "Kirei", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }
}
