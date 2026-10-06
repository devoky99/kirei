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
/// Datenschutz-Manifest klein bleibt. Ab Phase 1 übernimmt SwiftData.
public struct ScanStateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "scan-state.json")
    }

    /// Ablage unter „Application Support/Kirei“, auf dem Mac im Sandbox-Container.
    public static func standard() throws -> ScanStateStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Kirei", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ScanStateStore(directory: directory)
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
