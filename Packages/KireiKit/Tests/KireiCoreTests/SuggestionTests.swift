import Foundation
import Testing
@testable import KireiCore

@Suite("Ähnliche Fotos gruppieren")
struct SimilarityGrouperTests {
    private func group(_ photos: [AnalyzedPhoto], settings: SuggestionSettings = .default) -> [[String]] {
        var grouper = SimilarityGrouper(settings: settings)
        var clusters: [SimilarityGrouper.Cluster] = []
        for photo in photos {
            if let candidate = GroupingCandidate(photo: photo) {
                grouper.add(candidate)
            }
            clusters += grouper.drainClosed()
        }
        clusters += grouper.finish()
        return clusters.map { $0.members.map(\.id.rawValue) }
    }

    @Test("Fast gleiche Fotos kurz nacheinander bilden eine Gruppe")
    func nearPhotosGroup() {
        let groups = group([
            analyzed("a", at: 0, print: testPrint(axis: 0)),
            analyzed("b", at: 20, print: testPrint(axis: 0, nudge: 0.1)),
            analyzed("c", at: 40, print: testPrint(axis: 3)),
        ])
        #expect(groups == [["a", "b"]])
    }

    @Test("Jedes Mitglied muss jedem ähnlich sein, keine Ketten")
    func noChaining() {
        let groups = group([
            analyzed("a", at: 0, print: testPrint(axis: 0)),
            analyzed("b", at: 10, print: testPrint(axis: 0, nudge: 0.2)),
            analyzed("c", at: 20, print: testPrint(axis: 0, nudge: 0.4)),
        ])
        #expect(groups == [["a", "b"]])
    }

    @Test("Zu lange Pause trennt die Gruppe")
    func gapSplits() {
        let groups = group([
            analyzed("a", at: 0, print: testPrint(axis: 0)),
            analyzed("b", at: 30, print: testPrint(axis: 0, nudge: 0.1)),
            analyzed("c", at: 300, print: testPrint(axis: 0)),
            analyzed("d", at: 310, print: testPrint(axis: 0, nudge: 0.1)),
        ])
        #expect(groups == [["a", "b"], ["c", "d"]])
    }

    @Test("Abwechselnde Motive landen in getrennten Gruppen")
    func interleavedSubjects() {
        let groups = group([
            analyzed("a", at: 0, print: testPrint(axis: 0)),
            analyzed("x", at: 10, print: testPrint(axis: 4)),
            analyzed("b", at: 20, print: testPrint(axis: 0, nudge: 0.1)),
            analyzed("y", at: 30, print: testPrint(axis: 4, nudge: 0.1)),
        ]).sorted { $0[0] < $1[0] }
        #expect(groups == [["a", "b"], ["x", "y"]])
    }

    @Test("Eine Gruppe dauert höchstens zehn Minuten")
    func maxSpan() {
        let photos = (0..<15).map { analyzed("p\($0)", at: Double($0) * 50, print: testPrint(axis: 0)) }
        let groups = group(photos)
        #expect(groups.count == 2)
        #expect(groups[0].count == 13)
    }

    @Test("Fotos ohne Datum oder Merkmale werden übergangen")
    func missingData() {
        let undated = AnalyzedPhoto(id: AssetID("u"), date: nil, featurePrint: testPrint(axis: 0), aestheticScore: nil, isUtility: false, sharpness: 0)
        #expect(GroupingCandidate(photo: undated) == nil)
        #expect(GroupingCandidate(photo: analyzed("n", at: 0, print: nil)) == nil)
    }
}

@Suite("Bestes Foto wählen")
struct BestShotPickerTests {
    private func member(
        _ id: String,
        at seconds: TimeInterval,
        sharpness: Double = 100,
        aesthetic: Float = 0.2,
        eyes: Double? = nil,
        favorite: Bool = false
    ) -> GroupMember {
        GroupMember(
            record: photo(id, at: seconds, favorite: favorite),
            photo: analyzed(id, at: seconds, print: testPrint(axis: 0), aesthetic: aesthetic, sharpness: sharpness),
            faces: eyes.map { FaceSummary(faceCount: 1, minEyeOpenness: $0, meanCaptureQuality: 0.5) }
        )
    }

    @Test("Das schärfste Foto bleibt, die anderen sind begründet")
    func keepsSharpest() throws {
        let group = try #require(BestShotPicker.makeGroup([
            member("a", at: 0, sharpness: 100),
            member("b", at: 5, sharpness: 300),
        ], settings: .default))

        let keep = try #require(group.items.first)
        #expect(keep.assetID == AssetID("b"))
        #expect(keep.role == .keep)
        #expect(keep.reasons.contains(.sharpest))

        let other = try #require(group.suggested.first)
        #expect(other.assetID == AssetID("a"))
        #expect(other.reasons == [.nearlyIdentical, .lessSharp])
        #expect(group.items.allSatisfy { !$0.isPreselected })
    }

    @Test("Geschlossene Augen verlieren, auch bei besserer Qualität")
    func eyesClosedLoses() throws {
        let group = try #require(BestShotPicker.makeGroup([
            member("a", at: 0, sharpness: 400, aesthetic: 0.8, eyes: 0.05),
            member("b", at: 5, sharpness: 300, aesthetic: 0.3, eyes: 0.3),
        ], settings: .default))

        #expect(group.items[0].assetID == AssetID("b"))
        #expect(group.items[0].reasons.contains(.eyesOpen))
        #expect(group.suggested.first?.reasons.contains(.eyesClosed) == true)
    }

    @Test("Ein Favorit bleibt immer, auch wenn er schwächer ist")
    func favoriteStays() throws {
        let group = try #require(BestShotPicker.makeGroup([
            member("a", at: 0, sharpness: 50, favorite: true),
            member("b", at: 5, sharpness: 300),
        ], settings: .default))

        #expect(group.items[0].assetID == AssetID("a"))
        #expect(group.items[0].reasons.contains(.protected(.favorite)))
        #expect(group.suggested.map(\.assetID) == [AssetID("b")])
    }

    @Test("Nur geschützte Fotos ergeben keine Gruppe")
    func onlyProtected() {
        let group = BestShotPicker.makeGroup([
            member("a", at: 0, favorite: true),
            member("b", at: 5, favorite: true),
        ], settings: .default)
        #expect(group == nil)
    }
}

@Suite("Exakte Duplikate")
struct DuplicateFinderTests {
    private let records = [
        photo("a", at: 100),
        photo("b", at: 100),
        photo("c", at: 200),
    ]

    @Test("Kandidaten brauchen gleiche Maße und gleiche Aufnahmezeit")
    func candidates() {
        let buckets = DuplicateFinder.candidates(in: records)
        #expect(buckets.map { $0.map(\.id.rawValue) } == [["a", "b"]])
    }

    @Test("Serienbilder sind keine Duplikate")
    func burstsExcluded() {
        let frames = [
            AssetRecord(id: AssetID("f1"), kind: .photo, traits: .burst, creationDate: .distantPast, pixelWidth: 10, pixelHeight: 10, burstIdentifier: "x"),
            AssetRecord(id: AssetID("f2"), kind: .photo, traits: .burst, creationDate: .distantPast, pixelWidth: 10, pixelHeight: 10, burstIdentifier: "x"),
        ]
        #expect(DuplicateFinder.candidates(in: frames).isEmpty)
    }

    @Test("Bearbeitete und unbearbeitete, Live Photo und Standbild sind keine Kandidaten")
    func editsAndLivePhotosAreDistinct() {
        let base = photo("a", at: 100)
        let edited = AssetRecord(id: AssetID("b"), kind: .photo, creationDate: base.creationDate, pixelWidth: base.pixelWidth, pixelHeight: base.pixelHeight, hasAdjustments: true)
        let live = AssetRecord(id: AssetID("c"), kind: .photo, traits: .livePhoto, creationDate: base.creationDate, pixelWidth: base.pixelWidth, pixelHeight: base.pixelHeight)
        #expect(DuplicateFinder.candidates(in: [base, edited, live]).isEmpty)
    }

    @Test("Gleiche Prüfsumme: exakte Kopie, vorausgewählt")
    func confirmedCopy() throws {
        let groups = DuplicateFinder.resolve(
            candidates: DuplicateFinder.candidates(in: records),
            hashes: [AssetID("a"): Data([1]), AssetID("b"): Data([1])],
            settings: .default
        )
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.items[0].reasons == [.original])
        #expect(group.suggested.map(\.reasons) == [[.exactCopy]])
        #expect(group.suggested.allSatisfy { $0.isPreselected })
    }

    @Test("Ohne Prüfsumme, etwa weil das Original nur in iCloud liegt, keine Duplikat-Gruppe")
    func unconfirmedIsNoDuplicate() {
        let groups = DuplicateFinder.resolve(
            candidates: DuplicateFinder.candidates(in: records),
            hashes: [AssetID("a"): Data([1])],
            settings: .default
        )
        #expect(groups.isEmpty)
    }

    @Test("Verschiedene Prüfsummen sind keine Kopien")
    func differentHashes() {
        let groups = DuplicateFinder.resolve(
            candidates: DuplicateFinder.candidates(in: records),
            hashes: [AssetID("a"): Data([1]), AssetID("b"): Data([2])],
            settings: .default
        )
        #expect(groups.isEmpty)
    }

    @Test("Ein geschützter Eintrag wird behalten, nie vorgeschlagen")
    func protectedCopy() throws {
        let favorite = [photo("a", at: 100), photo("b", at: 100, favorite: true)]
        let groups = DuplicateFinder.resolve(
            candidates: DuplicateFinder.candidates(in: favorite),
            hashes: [AssetID("a"): Data([1]), AssetID("b"): Data([1])],
            settings: .default
        )
        let group = try #require(groups.first)
        #expect(group.items[0].assetID == AssetID("b"))
        #expect(group.suggested.map(\.assetID) == [AssetID("a")])
    }
}

@Suite("Vorschläge aus Metadaten")
struct MetadataSuggestionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func screenshot(_ id: String, daysAgo: Double, favorite: Bool = false) -> AssetRecord {
        AssetRecord(
            id: AssetID(id),
            kind: .photo,
            traits: .screenshot,
            creationDate: now.addingTimeInterval(-daysAgo * 86_400),
            pixelWidth: 1179,
            pixelHeight: 2556,
            isFavorite: favorite
        )
    }

    private func video(_ id: String, seconds: Double, recording: Bool = false) -> AssetRecord {
        AssetRecord(
            id: AssetID(id),
            kind: .video,
            traits: recording ? .screenRecording : [],
            creationDate: now,
            pixelWidth: 3840,
            pixelHeight: 2160,
            duration: seconds
        )
    }

    @Test("Nur Bildschirmfotos ab 30 Tagen, älteste zuerst, keine Favoriten")
    func screenshots() throws {
        let group = try #require(SuggestionBuilder.screenshotGroup(
            records: [
                screenshot("new", daysAgo: 10),
                screenshot("month", daysAgo: 40),
                screenshot("year", daysAgo: 400),
                screenshot("fav", daysAgo: 500, favorite: true),
            ],
            settings: .default,
            now: now
        ))
        #expect(group.items.map(\.assetID.rawValue) == ["year", "month"])
        #expect(group.items[0].reasons == [.screenshot(ageInDays: 400)])
        #expect(group.items.allSatisfy { !$0.isPreselected })
    }

    @Test("Große Videos nach Größe, Bildschirmaufnahmen getrennt")
    func videos() throws {
        let records = [
            video("short", seconds: 5),
            video("long", seconds: 120),
            video("medium", seconds: 40),
            video("screen", seconds: 300, recording: true),
        ]
        let large = try #require(SuggestionBuilder.largeVideoGroup(records: records, settings: .default))
        #expect(large.items.map(\.assetID.rawValue) == ["long", "medium"])

        let recordings = try #require(SuggestionBuilder.screenRecordingGroup(records: records, settings: .default))
        #expect(recordings.items.map(\.reasons) == [[.screenRecording(seconds: 300)]])
    }

    @Test("Serie: behalten wird, was sichtbar oder gut markiert ist")
    func burstWithoutUserPick() throws {
        func frame(_ id: String, _ seconds: Double, _ traits: AssetTraits) -> AssetRecord {
            AssetRecord(id: AssetID(id), kind: .photo, traits: traits.union(.burst), creationDate: now.addingTimeInterval(seconds), burstIdentifier: "s")
        }
        let groups = SuggestionBuilder.burstGroups(records: [
            frame("1", 0, .burstRepresentative),
            frame("2", 0.1, .burstAutoPick),
            frame("3", 0.2, []),
            frame("4", 0.3, []),
        ], settings: .default)
        let group = try #require(groups.first)
        #expect(group.items.filter { $0.role == .keep }.map(\.assetID.rawValue) == ["1", "2"])
        #expect(group.suggested.map(\.assetID.rawValue) == ["3", "4"])
        #expect(group.suggested.allSatisfy { $0.reasons == [.unselectedBurstFrame] })
    }

    @Test("Serie mit eigener Auswahl: nur die Auswahl bleibt")
    func burstWithUserPick() throws {
        func frame(_ id: String, _ seconds: Double, _ traits: AssetTraits) -> AssetRecord {
            AssetRecord(id: AssetID(id), kind: .photo, traits: traits.union(.burst), creationDate: now.addingTimeInterval(seconds), burstIdentifier: "s")
        }
        let groups = SuggestionBuilder.burstGroups(records: [
            frame("1", 0, .burstRepresentative),
            frame("2", 0.1, .burstAutoPick),
            frame("3", 0.2, .burstUserPick),
        ], settings: .default)
        let group = try #require(groups.first)
        #expect(group.suggested.map(\.assetID.rawValue) == ["2"])
    }

    @Test("Unscharf nur, wenn beide Messungen niedrig sind und kein Gebrauchsbild")
    func blurry() {
        let settings = SuggestionSettings.default
        #expect(SuggestionBuilder.isBlurry(analyzed("a", at: 0, print: nil, aesthetic: -0.7, sharpness: 10), settings: settings))
        #expect(!SuggestionBuilder.isBlurry(analyzed("b", at: 0, print: nil, aesthetic: -0.7, sharpness: 500), settings: settings))
        #expect(!SuggestionBuilder.isBlurry(analyzed("c", at: 0, print: nil, aesthetic: 0.2, sharpness: 10), settings: settings))
        #expect(!SuggestionBuilder.isBlurry(analyzed("d", at: 0, print: nil, aesthetic: -0.7, sharpness: 10, utility: true), settings: settings))
    }

    @Test("Gruppen erscheinen in der Reihenfolge der Kategorien")
    func ordering() {
        let groups = [
            SuggestionGroup(id: "v", category: .largeVideos, items: []),
            SuggestionGroup(id: "s1", category: .similar, items: []),
            SuggestionGroup(id: "d", category: .exactDuplicates, items: []),
            SuggestionGroup(id: "s2", category: .similar, items: []),
        ]
        #expect(SuggestionBuilder.ordered(groups).map(\.id) == ["d", "s1", "s2", "v"])
    }
}

@Suite("Trefferquote und Kalibrierung")
struct QualityTests {
    @Test("Prüfpunkt 1 verlangt eine Untergrenze über 98 %")
    func gate() {
        #expect(PrecisionEstimate(correct: 990, total: 1_000).meets(target: 0.98, minimumCount: 1_000))
        #expect(!PrecisionEstimate(correct: 980, total: 1_000).meets(target: 0.98, minimumCount: 1_000))
        #expect(!PrecisionEstimate(correct: 200, total: 200).meets(target: 0.98, minimumCount: 1_000))
        #expect(abs(PrecisionEstimate(correct: 990, total: 1_000).lowerBound - 0.9817) < 0.0005)
    }

    @Test("Wenige Markierungen: Empfehlung ohne Fehler, aber nicht abgesichert")
    func fewLabels() throws {
        let recommendation = try #require(ThresholdCalibration.recommend(
            positives: [0.1, 0.15, 0.2],
            negatives: [0.5, 0.6],
            target: 0.98
        ))
        #expect(recommendation.point.threshold == 0.2)
        #expect(!recommendation.isStatisticallySafe)
    }

    @Test("Ohne Gegenbeispiele gibt es keine abgesicherte Empfehlung")
    func noNegatives() throws {
        let positives = (0..<400).map { 0.05 + Double($0) / 2_000 }
        let recommendation = try #require(ThresholdCalibration.recommend(positives: positives, negatives: [], target: 0.98))
        #expect(!recommendation.isStatisticallySafe)
    }

    @Test("Auswertung zählt Treffer und Fehler je Schwelle")
    func sweepCounts() {
        let points = ThresholdCalibration.sweep(positives: [0.1, 0.3, 0.3], negatives: [0.2, 0.5])
        #expect(points.map(\.threshold) == [0.1, 0.2, 0.3, 0.5])
        #expect(points.map(\.truePositives) == [1, 1, 3, 3])
        #expect(points.map(\.falsePositives) == [0, 1, 1, 2])
    }

    @Test("Viele Markierungen: abgesicherte Empfehlung")
    func manyLabels() throws {
        let positives = (0..<400).map { 0.05 + Double($0) / 2_000 }
        let negatives = (0..<100).map { 0.6 + Double($0) / 1_000 }
        let recommendation = try #require(ThresholdCalibration.recommend(positives: positives, negatives: negatives, target: 0.98))
        #expect(recommendation.isStatisticallySafe)
        #expect(recommendation.point.falsePositives == 0)
        #expect(recommendation.point.recall == 1)
    }
}
