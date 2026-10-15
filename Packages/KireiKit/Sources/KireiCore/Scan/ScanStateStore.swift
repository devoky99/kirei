import Foundation

/// Was zwischen zwei Starts erhalten bleibt.
public struct ScanState: Sendable, Codable, Equatable {
    public var changeToken: ChangeToken?
    public var lastScan: Date?

    public init(changeToken: ChangeToken? = nil, lastScan: Date? = nil) {
        self.changeToken = changeToken
        self.lastScan = lastScan
    }
}

/// Speichert den Scan-Stand als kleine JSON-Datei im App-Container.
///
/// Absichtlich keine UserDefaults und keine Datei-Zeitstempel, damit das
/// Datenschutz-Manifest klein bleibt. Die Analysen selbst liegen im Index.
public struct ScanStateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "scan-state.json")
    }

    /// Ablage in Kireis eigenem Ordner, ohne Backup.
    public static func standard() throws -> ScanStateStore {
        ScanStateStore(directory: try KireiStorage.directory())
    }

    public func load() -> ScanState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ScanState.self, from: data)
    }

    public func save(_ state: ScanState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
