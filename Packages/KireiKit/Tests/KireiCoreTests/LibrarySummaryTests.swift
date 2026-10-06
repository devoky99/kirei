import Testing
@testable import KireiCore

@Suite("Mediathek zählen")
struct LibrarySummaryTests {
    @Test("Bildschirmfotos zählen nicht als Fotos")
    func screenshotsAreSeparate() {
        let records = [
            AssetRecord(id: AssetID("a"), kind: .photo),
            AssetRecord(id: AssetID("b"), kind: .photo, traits: .screenshot),
            AssetRecord(id: AssetID("c"), kind: .video),
            AssetRecord(id: AssetID("d"), kind: .photo, traits: [.burst, .livePhoto]),
            AssetRecord(id: AssetID("e"), kind: .other),
        ]

        let summary = LibrarySummary(records: records)

        #expect(summary == LibrarySummary(photos: 2, videos: 1, screenshots: 1))
    }

    @Test("Leere Mediathek")
    func emptyLibrary() {
        #expect(LibrarySummary(records: []) == .empty)
    }
}

@Suite("Berechtigung")
struct LibraryAccessTests {
    @Test("Nur Teil- und Vollzugriff dürfen lesen", arguments: [
        (LibraryAccess.notDetermined, false),
        (.denied, false),
        (.restricted, false),
        (.limited, true),
        (.full, true),
    ])
    func canRead(access: LibraryAccess, expected: Bool) {
        #expect(access.canRead == expected)
    }
}
