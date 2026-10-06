import Foundation
import Testing
@testable import KireiCore

#if canImport(Photos)
import Photos
#endif

@Suite("Grundsätze des Scans")
struct ScanRulesTests {
    @Test("Der Scan nutzt nie das Netz")
    func policyForbidsNetwork() {
        #expect(ScanPolicy.allowsNetworkAccess == false)
    }

    #if canImport(Photos)
    @Test("Vorschaubilder werden nie aus iCloud geladen")
    func thumbnailOptionsForbidNetwork() {
        let options = PhotoKitSource.makeThumbnailOptions()
        #expect(options.isNetworkAccessAllowed == false)
        #expect(options.deliveryMode == .highQualityFormat)
    }
    #endif
}

@Suite("Änderungen zusammenfassen")
struct LibraryChangesTests {
    @Test("Später gelöscht gewinnt")
    func deletedWins() {
        var changes = LibraryChanges(inserted: [AssetID("a")], updated: [AssetID("b")])
        changes.merge(LibraryChanges(deleted: [AssetID("a"), AssetID("b")]))

        #expect(changes.inserted.isEmpty)
        #expect(changes.updated.isEmpty)
        #expect(changes.deleted == [AssetID("a"), AssetID("b")])
    }

    @Test("Neu und danach geändert bleibt neu")
    func insertedThenUpdatedStaysInserted() {
        var changes = LibraryChanges(inserted: [AssetID("a")])
        changes.merge(LibraryChanges(updated: [AssetID("a")]))

        #expect(changes.inserted == [AssetID("a")])
        #expect(changes.updated.isEmpty)
    }
}

@Suite("Scan-Stand speichern")
struct ScanStateStoreTests {
    @Test("Speichern und wieder laden")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kirei-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ScanStateStore(directory: directory)
        #expect(store.load() == nil)

        let state = ScanState(
            changeToken: ChangeToken(data: Data([1, 2, 3])),
            lastScan: Date(timeIntervalSince1970: 1_000)
        )
        try store.save(state)

        #expect(store.load() == state)
    }
}
