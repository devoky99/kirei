import Foundation
import KireiCore
import Observation

/// Zustand der Mediathek für die Oberfläche, auf allen Geräten gleich.
///
/// Entscheidet nichts über Fotos. Das macht der Kern, dieses Modell reicht
/// nur weiter und merkt sich, was die Ansicht zeigen soll.
@MainActor
@Observable
final class LibraryModel {
    private(set) var access: LibraryAccess
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var failed = false
    private(set) var progress: ScanProgress?
    private(set) var results: ScanResults = .empty
    /// Einträge, die Fotos als eigenes Bild zeigt. Für das Raster.
    private(set) var records: [AssetRecord] = []
    /// Neue Einträge seit dem letzten Start, `nil` beim ersten Mal.
    private(set) var newSinceLastScan: Int?

    private let source: any PhotoSource & LibraryChangeTracker
    private let scanner: LibraryScanner?
    private let stateStore: ScanStateStore?

    init(
        source: some PhotoSource & LibraryChangeTracker,
        analyzer: some ImageAnalyzer,
        hasher: (any ContentHasher)?,
        index: AssetIndex? = try? .standard(),
        stateStore: ScanStateStore? = try? .standard()
    ) {
        self.source = source
        self.stateStore = stateStore
        self.access = source.access()
        self.scanner = index.map { index in
            LibraryScanner(source: source, analyzer: analyzer, hasher: hasher, index: index)
        }
    }

    func requestAccess() async {
        access = await source.requestAccess()
        if access.canRead {
            startScan()
        }
    }

    /// Startet einen Scan, falls keiner läuft.
    func startScan() {
        guard access.canRead, !isScanning, let scanner else { return }
        isScanning = true
        failed = false

        Task {
            do {
                let final = try await scanner.scan { [weak self] update in
                    await self?.apply(update)
                }
                results = final
            } catch is CancellationError {
                // Abgebrochen, der Zwischenstand bleibt sichtbar.
            } catch {
                failed = true
            }
            progress = nil
            isScanning = false
            hasScanned = true
            newSinceLastScan = await updateScanState()
        }
    }

    func thumbnail(for id: AssetID, pixelSize: Int = ScanPolicy.gridThumbnailPixelSize) async -> Thumbnail? {
        await source.thumbnail(for: id, maxPixelSize: pixelSize, mode: .fill)
    }

    private func apply(_ update: ScanUpdate) {
        switch update {
        case .progress(let progress):
            self.progress = progress.stage == .finished ? nil : progress
        case .records(let records):
            self.records = records.filter(\.isVisibleInLibrary)
        case .results(let results):
            self.results = results
        }
    }

    /// Fragt nach Änderungen seit dem letzten Start und merkt sich den neuen Stand.
    private func updateScanState() async -> Int? {
        guard let stateStore else { return nil }
        var state = stateStore.load() ?? ScanState()

        var newCount: Int?
        if let previous = state.changeToken,
           case .changes(let changes)? = try? await source.changes(since: previous) {
            newCount = changes.inserted.count
        }

        state.changeToken = try? await source.currentChangeToken()
        state.lastScan = .now
        try? stateStore.save(state)
        return newCount
    }
}
