import Foundation
import Testing
@testable import KireiCore

@Suite("Index")
struct AssetIndexTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Neu, geändert und verschwunden werden erkannt")
    func sync() async throws {
        let index = try AssetIndex.inMemory()
        let first = try await index.sync([photo("a", at: 0), photo("b", at: 10)])
        #expect(first == IndexSyncResult(inserted: 2, updated: 0, removed: 0))

        let edited = AssetRecord(
            id: AssetID("a"),
            kind: .photo,
            creationDate: base,
            modificationDate: base.addingTimeInterval(60),
            hasAdjustments: true
        )
        let second = try await index.sync([edited, photo("c", at: 20)])
        #expect(second == IndexSyncResult(inserted: 1, updated: 1, removed: 1))
    }

    @Test("Offene Analysen: nur Fotos, neueste zuerst, danach erledigt")
    func pendingAnalysis() async throws {
        let index = try AssetIndex.inMemory()
        let screenshot = AssetRecord(id: AssetID("s"), kind: .photo, traits: .screenshot, creationDate: base)
        let video = AssetRecord(id: AssetID("v"), kind: .video, creationDate: base)
        try await index.sync([photo("old", at: 0), photo("new", at: 100), screenshot, video])

        let pending = try await index.pendingAnalysis(version: 1, limit: 10)
        #expect(pending == [AssetID("new"), AssetID("old")])

        let analysis = ImageAnalysis(featurePrint: testPrint(axis: 1), aestheticScore: 0.5, isUtility: false, sharpness: 42)
        try await index.save(analyses: [
            AnalysisOutcome(id: AssetID("new"), analysis: analysis),
            AnalysisOutcome(id: AssetID("old"), analysis: nil),
        ], version: 1)

        #expect(try await index.pendingAnalysis(version: 1, limit: 10).isEmpty)
        #expect(try await index.analysisCounts(version: 1) == AnalysisCounts(analyzable: 2, processed: 2, unavailable: 1))

        let photos = try await index.analyzedPhotos(version: 1, after: nil, limit: 10).photos
        #expect(photos.map(\.id) == [AssetID("new")])
        #expect(photos.first?.featurePrint == testPrint(axis: 1))
        #expect(photos.first?.sharpness == 42)

        // Eine neue Analyseversion rechnet alles neu.
        #expect(try await index.pendingAnalysis(version: 2, limit: 10).count == 2)

        // Ohne Vorschaubild wird es beim nächsten Scan erneut versucht.
        try await index.retryUnavailable()
        #expect(try await index.pendingAnalysis(version: 1, limit: 10) == [AssetID("old")])
    }

    @Test("Seitenweises Lesen liefert jedes Foto genau einmal, auch bei gleichem Datum")
    func pagingWithCursor() async throws {
        let index = try AssetIndex.inMemory()
        // Fünf Fotos, drei davon mit derselben Aufnahmezeit.
        let records = [photo("e", at: 30), photo("a", at: 10), photo("c", at: 10), photo("b", at: 10), photo("d", at: 20)]
        try await index.sync(records)
        let analysis = ImageAnalysis(featurePrint: nil, aestheticScore: 0, isUtility: false, sharpness: 1)
        try await index.save(analyses: records.map { AnalysisOutcome(id: $0.id, analysis: analysis) }, version: 1)

        var seen: [String] = []
        var cursor: IndexCursor?
        while true {
            let page = try await index.analyzedPhotos(version: 1, after: cursor, limit: 2)
            seen += page.photos.map(\.id.rawValue)
            guard let next = page.next else { break }
            cursor = next
        }
        #expect(seen == ["a", "b", "c", "d", "e"])
    }

    @Test("Zweiter Abgleich ohne Änderungen setzt nichts zurück, auch bei Zahlen in Kennungen")
    func repeatedSyncKeepsAnalysis() async throws {
        let index = try AssetIndex.inMemory()
        // Kennungen, die „natürlich“ und Zeichen für Zeichen verschieden sortieren.
        let records = (0..<25).map { photo("item-\($0)", at: Double($0 % 5)) }
        try await index.sync(records)
        let analysis = ImageAnalysis(featurePrint: nil, aestheticScore: 0, isUtility: false, sharpness: 1)
        try await index.save(analyses: records.map { AnalysisOutcome(id: $0.id, analysis: analysis) }, version: 1)

        let again = try await index.sync(records)
        #expect(again == IndexSyncResult(inserted: 0, updated: 0, removed: 0))
        #expect(try await index.pendingAnalysis(version: 1, limit: 100).isEmpty)
    }

    @Test("Bearbeitete Fotos werden neu analysiert")
    func editResetsAnalysis() async throws {
        let index = try AssetIndex.inMemory()
        try await index.sync([photo("a", at: 0)])
        try await index.save(analyses: [
            AnalysisOutcome(id: AssetID("a"), analysis: ImageAnalysis(featurePrint: nil, aestheticScore: 0, isUtility: false, sharpness: 1)),
        ], version: 1)
        #expect(try await index.pendingAnalysis(version: 1, limit: 10).isEmpty)

        let edited = AssetRecord(id: AssetID("a"), kind: .photo, creationDate: photo("a", at: 0).creationDate, modificationDate: .now)
        try await index.sync([edited])
        #expect(try await index.pendingAnalysis(version: 1, limit: 10) == [AssetID("a")])
    }

    @Test("Gesichter und Prüfsummen bleiben gespeichert")
    func facesAndHashes() async throws {
        let index = try AssetIndex.inMemory()
        try await index.sync([photo("a", at: 0), photo("b", at: 10)])

        #expect(try await index.pendingFaces(among: [AssetID("a"), AssetID("b")], version: 1).count == 2)
        let faces = FaceSummary(faceCount: 2, minEyeOpenness: 0.3, meanCaptureQuality: 0.6)
        try await index.save(faces: [FaceOutcome(id: AssetID("a"), faces: faces)], version: 1)
        #expect(try await index.pendingFaces(among: [AssetID("a"), AssetID("b")], version: 1) == [AssetID("b")])
        #expect(try await index.faces(for: [AssetID("a")], version: 1) == [AssetID("a"): faces])

        try await index.save(contentHashes: [AssetID("b"): Data([9, 9])])
        #expect(try await index.contentHashes(for: [AssetID("a"), AssetID("b")]) == [AssetID("b"): Data([9, 9])])
    }
}

/// Zählt, wie oft analysiert wurde.
actor CallCounter {
    private(set) var count = 0

    func increment() { count += 1 }
}

/// Sammelt die Meldungen des Scanners.
actor UpdateLog {
    private(set) var updates: [ScanUpdate] = []

    func append(_ update: ScanUpdate) { updates.append(update) }

    var sawRecords: Bool {
        updates.contains { if case .records = $0 { return true } else { return false } }
    }

    var partialResults: Int {
        updates.filter { if case .results(let results) = $0 { return !results.isComplete } else { return false } }.count
    }
}

/// Zählt die Aufrufe und reicht an `FakeAnalyzer` weiter.
struct CountingAnalyzer: ImageAnalyzer {
    let inner: FakeAnalyzer
    let counter: CallCounter

    var version: Int { inner.version }

    func analyze(_ thumbnail: Thumbnail) async throws -> ImageAnalysis {
        await counter.increment()
        return try await inner.analyze(thumbnail)
    }

    func analyzeFaces(_ thumbnail: Thumbnail) async throws -> FaceSummary {
        try await inner.analyzeFaces(thumbnail)
    }
}

@Suite("Scanner von Anfang bis Ende")
struct LibraryScannerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000 + 2_000)

    private var records: [AssetRecord] {
        [
            photo("p1", at: 0),
            photo("p2", at: 20),
            photo("p3", at: 40),
            photo("d1", at: 1_000),
            photo("d2", at: 1_000),
            photo("cloud", at: 1_500),
            // Zwei sichtbare Bilder einer Serie: gehören zu „Serien“, nicht zu „ähnlich“.
            AssetRecord(id: AssetID("b1"), kind: .photo, traits: [.burst, .burstRepresentative], creationDate: Date(timeIntervalSinceReferenceDate: 800_003_000), burstIdentifier: "serie"),
            AssetRecord(id: AssetID("b2"), kind: .photo, traits: [.burst, .burstUserPick], creationDate: Date(timeIntervalSinceReferenceDate: 800_003_001), burstIdentifier: "serie"),
            AssetRecord(
                id: AssetID("shot"),
                kind: .photo,
                traits: .screenshot,
                creationDate: now.addingTimeInterval(-400 * 86_400),
                pixelWidth: 1179,
                pixelHeight: 2556
            ),
        ]
    }

    private func analysis(_ print: FeaturePrint, sharpness: Double = 100) -> ImageAnalysis {
        ImageAnalysis(featurePrint: print, aestheticScore: 0.2, isUtility: false, sharpness: sharpness)
    }

    private func makeScanner(counter: CallCounter, index: AssetIndex) -> LibraryScanner {
        let records = records
        let analyzer = FakeAnalyzer(records: records, analyses: [
            AssetID("p1"): analysis(testPrint(axis: 0)),
            AssetID("p2"): analysis(testPrint(axis: 0, nudge: 0.1), sharpness: 300),
            AssetID("p3"): analysis(testPrint(axis: 4)),
            AssetID("d1"): analysis(testPrint(axis: 2)),
            AssetID("d2"): analysis(testPrint(axis: 2)),
            AssetID("b1"): analysis(testPrint(axis: 6)),
            // Unscharf, aber als Serienbild nicht unter „unscharf“.
            AssetID("b2"): ImageAnalysis(featurePrint: testPrint(axis: 6, nudge: 0.05), aestheticScore: -0.8, isUtility: false, sharpness: 5),
        ])
        let now = now
        return LibraryScanner(
            source: FakePhotoSource(records: records, cloudOnly: [AssetID("cloud")]),
            analyzer: CountingAnalyzer(inner: analyzer, counter: counter),
            hasher: FakeHasher(hashes: [AssetID("d1"): Data([1]), AssetID("d2"): Data([1])]),
            index: index,
            now: { now }
        )
    }

    @Test("Alle Kategorien, begründet, nur exakte Kopien vorausgewählt")
    func fullScan() async throws {
        let index = try AssetIndex.inMemory()
        let counter = CallCounter()
        let log = UpdateLog()
        let results = try await makeScanner(counter: counter, index: index).scan { await log.append($0) }

        #expect(results.isComplete)
        #expect(results.groups.map(\.category) == [.exactDuplicates, .similar, .screenshots])

        let duplicates = try #require(results.groups(in: .exactDuplicates).first)
        #expect(duplicates.suggested.map(\.assetID) == [AssetID("d2")])
        #expect(duplicates.suggested.allSatisfy { $0.isPreselected })

        let similar = try #require(results.groups(in: .similar).first)
        #expect(similar.items.first?.assetID == AssetID("p2"))
        #expect(similar.suggested.map(\.assetID) == [AssetID("p1")])
        #expect(similar.suggested.first?.reasons == [.nearlyIdentical, .lessSharp])

        let preselected = results.groups.flatMap(\.items).filter(\.isPreselected)
        #expect(preselected.allSatisfy { $0.reasons == [.exactCopy] })

        #expect(results.groups(in: .similar).count == 1)
        #expect(results.groups(in: .blurry).isEmpty)
        #expect(results.counts == AnalysisCounts(analyzable: 8, processed: 8, unavailable: 1))
        #expect(await counter.count == 7)

        let metrics = try #require(results.metrics)
        #expect(metrics.analyzedInThisRun == 7)
        #expect(metrics.peakMemoryBytes > 0)
        #expect(metrics.firstResultsSeconds <= metrics.totalSeconds)
        #expect(await log.sawRecords)
        #expect(await log.partialResults >= 1)
    }

    @Test("Der zweite Scan rechnet nichts neu")
    func incrementalScan() async throws {
        let index = try AssetIndex.inMemory()
        let counter = CallCounter()
        let scanner = makeScanner(counter: counter, index: index)

        let first = try await scanner.scan { _ in }
        let analysesAfterFirst = await counter.count
        let second = try await scanner.scan { _ in }

        #expect(await counter.count == analysesAfterFirst)
        #expect(second.groups == first.groups)
        #expect(second.metrics?.analyzedInThisRun == 0)
    }
}
