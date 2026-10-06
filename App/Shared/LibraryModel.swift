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
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var access: LibraryAccess
    private(set) var phase: Phase = .idle
    private(set) var records: [AssetRecord] = []
    private(set) var summary: LibrarySummary = .empty
    /// Neue Einträge seit dem letzten Start, `nil` beim ersten Mal.
    private(set) var newSinceLastScan: Int?

    private let source: any PhotoSource & LibraryChangeTracker
    private let stateStore: ScanStateStore?

    init(source: some PhotoSource & LibraryChangeTracker, stateStore: ScanStateStore? = try? .standard()) {
        self.source = source
        self.stateStore = stateStore
        self.access = source.access()
    }

    func requestAccess() async {
        access = await source.requestAccess()
        if access.canRead {
            await refresh()
        }
    }

    func refresh() async {
        guard access.canRead, phase != .loading else { return }
        phase = .loading
        do {
            let fetched = try await source.fetchRecords()
            records = fetched
            summary = LibrarySummary(records: fetched)
            newSinceLastScan = await updateScanState()
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    func thumbnail(for id: AssetID) async -> Thumbnail? {
        await source.thumbnail(for: id, maxPixelSize: ScanPolicy.gridThumbnailPixelSize)
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
