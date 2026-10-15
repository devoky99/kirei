import Foundation
import Testing
@testable import KireiCore

@Suite("Prüfmodus")
struct ReviewTests {
    private func similarGroup(_ id: String, keep: String, suggested: [(String, Float)]) -> SuggestionGroup {
        var items = [SuggestionItem(assetID: AssetID(keep), role: .keep, reasons: [.bestOfGroup])]
        for (asset, distance) in suggested {
            items.append(SuggestionItem(assetID: AssetID(asset), role: .remove, reasons: [.nearlyIdentical], distanceToKeep: distance))
        }
        return SuggestionGroup(id: id, category: .similar, items: items)
    }

    private var results: ScanResults {
        ScanResults(
            groups: [
                SuggestionGroup(id: "dup", category: .exactDuplicates, items: [
                    SuggestionItem(assetID: AssetID("x"), role: .keep, reasons: [.original]),
                    SuggestionItem(assetID: AssetID("y"), role: .remove, reasons: [.exactCopy], isPreselected: true),
                ]),
                similarGroup("g1", keep: "a", suggested: [("b", 0.12), ("c", 0.2)]),
                similarGroup("g2", keep: "d", suggested: [("e", 0.25)]),
            ],
            summary: .empty,
            counts: AnalysisCounts(analyzable: 5, processed: 5, unavailable: 0),
            isComplete: true
        )
    }

    @Test("Nur Vorschläge „ähnlich“ kommen in den Prüfmodus, mit Abstand")
    func pairsFromResults() {
        let pairs = ReviewPair.pairs(from: results)
        #expect(pairs.map(\.suggested.rawValue) == ["b", "c", "e"])
        #expect(pairs.map(\.groupNumber) == [1, 1, 2])
        #expect(pairs.map(\.keep.rawValue) == ["a", "a", "d"])
        #expect(pairs.first?.distance == 0.12)
    }

    @Test("Urteile zählen, offene überspringen, beim ersten offenen weitermachen")
    func logEstimate() {
        let pairs = ReviewPair.pairs(from: results)
        var log = ReviewLog()
        log[pairs[0]] = .correct
        log[pairs[2]] = .wrong

        #expect(log.estimate(for: pairs) == PrecisionEstimate(correct: 1, total: 2))
        #expect(log.firstOpenIndex(in: pairs) == 1)

        log[pairs[1]] = .correct
        #expect(log.firstOpenIndex(in: pairs) == 2)
    }

    @Test("Urteile bleiben gespeichert")
    func storeRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kirei-review-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReviewStore(directory: directory)
        #expect(store.load() == ReviewLog())

        var log = ReviewLog()
        log[ReviewPair.pairs(from: results)[0]] = .wrong
        try store.save(log)
        #expect(store.load() == log)
    }

    @Test("Export ohne Kennungen, mit Messwerten und deutschen Urteilen")
    func exportCSV() {
        let pairs = ReviewPair.pairs(from: results)
        var log = ReviewLog()
        log[pairs[0]] = .correct
        log[pairs[1]] = .wrong
        let metrics = ScanMetrics(firstResultsSeconds: 2.5, analysisSeconds: 60, analyzedInThisRun: 600, totalSeconds: 70, peakMemoryBytes: 180_000_000)

        let csv = ReviewExport.csv(pairs: pairs, log: log, metrics: metrics, photoCount: 5_000)
        let lines = csv.split(separator: "\n").map(String.init)

        #expect(lines.contains("# Hochgerechnet auf 20.000 Fotos: 33.3 min"))
        #expect(lines.contains("# Spitzen-Speicher: 180 MB"))
        #expect(lines.contains("gruppe;abstand;gruende;urteil"))
        #expect(lines.contains("1;0.1200;nearlyIdentical;richtig"))
        #expect(lines.contains("1;0.2000;nearlyIdentical;falsch"))
        #expect(lines.contains("2;0.2500;nearlyIdentical;"))
        #expect(!csv.contains("\"a\"") && !csv.contains(";a;"))
    }

    @Test("Bestes-Foto-Wahl gibt den Abstand zum behaltenen Foto mit")
    func distanceFromPicker() throws {
        let members = [
            GroupMember(record: photo("a", at: 0), photo: analyzed("a", at: 0, print: testPrint(axis: 0), sharpness: 300), faces: nil),
            GroupMember(record: photo("b", at: 5), photo: analyzed("b", at: 5, print: testPrint(axis: 0, nudge: 0.1), sharpness: 100), faces: nil),
        ]
        let group = try #require(BestShotPicker.makeGroup(members, settings: .default))
        let distance = try #require(group.suggested.first?.distanceToKeep)
        #expect(abs(distance - 0.102) < 0.01)
    }
}
