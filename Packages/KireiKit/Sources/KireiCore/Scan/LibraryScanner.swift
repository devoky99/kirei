import Foundation

/// Liest die Mediathek, analysiert in Etappen und baut alle Vorschläge.
///
/// Ablauf:
/// 1. Metadaten lesen, Index abgleichen. Bildschirmfotos, Serien und große
///    Videos stehen danach sofort bereit.
/// 2. Fotos ohne aktuelle Analyse in kleinen Paketen analysieren, neueste
///    zuerst, mit Rücksicht auf Temperatur und Stromsparmodus.
/// 3. Exakte Duplikate bestätigen, ähnliche Fotos gruppieren.
/// 4. Gesichter nur für Fotos in Gruppen prüfen, bestes Foto wählen.
///
/// Nach dem ersten Scan rechnet Schritt 2 nur Neues und Geändertes.
public actor LibraryScanner {
    private let source: any PhotoSource
    private let analyzer: any ImageAnalyzer
    private let hasher: (any ContentHasher)?
    private let index: AssetIndex
    private let settings: SuggestionSettings
    private let now: @Sendable () -> Date

    /// Fotos pro Paket. Klein genug für häufige Fortschrittsmeldungen.
    static let batchSize = 48
    /// Seitengröße beim Lesen analysierter Fotos aus dem Index.
    static let pageSize = 2_000

    public init(
        source: any PhotoSource,
        analyzer: any ImageAnalyzer,
        hasher: (any ContentHasher)?,
        index: AssetIndex,
        settings: SuggestionSettings = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.analyzer = analyzer
        self.hasher = hasher
        self.index = index
        self.settings = settings
        self.now = now
    }

    @discardableResult
    public func scan(onUpdate: @escaping @Sendable (ScanUpdate) async -> Void) async throws -> ScanResults {
        // Auf dem Mac verhindert das, dass macOS die App beim Rechnen bremst (App Nap).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Analysing photos on this device"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let version = analyzer.version

        // 1. Metadaten
        await onUpdate(.progress(ScanProgress(stage: .reading)))
        let records = try await source.fetchRecords()
        await onUpdate(.records(records))
        let recordsByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        try await index.sync(records)

        let summary = LibrarySummary(records: records)
        let metadataGroups = SuggestionBuilder.metadataGroups(records: records, settings: settings, now: now())
        var counts = try await index.analysisCounts(version: version)
        await onUpdate(.results(ScanResults(
            groups: SuggestionBuilder.ordered(metadataGroups),
            summary: summary,
            counts: counts,
            isComplete: false
        )))

        // 2. Bildanalyse in Etappen
        try await analyzePending(version: version, onUpdate: onUpdate)
        counts = try await index.analysisCounts(version: version)

        // 3. Duplikate und ähnliche Fotos
        await onUpdate(.progress(ScanProgress(stage: .comparing)))
        let candidates = DuplicateFinder.candidates(in: records)
        let candidateIDs = candidates.flatMap { $0.map(\.id) }
        let hashes = try await contentHashes(for: candidateIDs)
        let candidatePrints = try await index.featurePrints(for: candidateIDs)
        let duplicateGroups = DuplicateFinder.resolve(
            candidates: candidates,
            hashes: hashes,
            prints: candidatePrints,
            settings: settings
        )
        let suggestedCopies = Set(duplicateGroups.flatMap { $0.suggested.map(\.assetID) })

        var grouper = SimilarityGrouper(settings: settings)
        var clusters: [SimilarityGrouper.Cluster] = []
        var blurCandidates: [AnalyzedPhoto] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await index.analyzedPhotos(version: version, offset: offset, limit: Self.pageSize)
            if page.isEmpty { break }
            offset += page.count
            for photo in page {
                guard let record = recordsByID[photo.id], record.isAnalyzable,
                      !suggestedCopies.contains(photo.id)
                else { continue }
                if SuggestionBuilder.isBlurry(photo, settings: settings) {
                    blurCandidates.append(photo)
                }
                if let candidate = GroupingCandidate(photo: photo) {
                    grouper.add(candidate)
                }
            }
            clusters += grouper.drainClosed()
        }
        clusters += grouper.finish()

        // 4. Gesichter und bestes Foto
        let clusteredIDs = clusters.flatMap { $0.members.map(\.id) }
        try await analyzeFaces(clusteredIDs, version: version, onUpdate: onUpdate)
        let faces = try await index.faces(for: clusteredIDs, version: version)

        let similarGroups = clusters.compactMap { cluster -> SuggestionGroup? in
            let members = cluster.members.compactMap { candidate -> GroupMember? in
                guard let record = recordsByID[candidate.id] else { return nil }
                return GroupMember(record: record, photo: candidate.photo, faces: faces[candidate.id])
            }
            return BestShotPicker.makeGroup(members, settings: settings)
        }

        let clustered = Set(clusteredIDs)
        let blurryGroup = SuggestionBuilder.blurryGroup(
            photos: blurCandidates.filter { !clustered.contains($0.id) },
            records: recordsByID,
            settings: settings
        )

        var groups = duplicateGroups + Array(similarGroups.reversed()) + metadataGroups
        if let blurryGroup {
            groups.append(blurryGroup)
        }

        let results = ScanResults(
            groups: SuggestionBuilder.ordered(groups),
            summary: summary,
            counts: counts,
            isComplete: true
        )
        await onUpdate(.progress(ScanProgress(stage: .finished)))
        await onUpdate(.results(results))
        return results
    }

    // MARK: Bildanalyse

    private func analyzePending(version: Int, onUpdate: @escaping @Sendable (ScanUpdate) async -> Void) async throws {
        var counts = try await index.analysisCounts(version: version)
        while true {
            try Task.checkCancellation()
            let ids = try await index.pendingAnalysis(version: version, limit: Self.batchSize)
            if ids.isEmpty { break }

            await onUpdate(.progress(ScanProgress(stage: .analyzing, completed: counts.processed, total: counts.analyzable)))
            let parallelism = try await AnalysisThrottle.waitForCapacity()
            let outcomes = await Self.analyzeBatch(ids, source: source, analyzer: analyzer, parallelism: parallelism)
            try await index.save(analyses: outcomes, version: version)
            counts.processed += outcomes.count
        }
    }

    private static func analyzeBatch(
        _ ids: [AssetID],
        source: any PhotoSource,
        analyzer: any ImageAnalyzer,
        parallelism: Int
    ) async -> [AnalysisOutcome] {
        await withTaskGroup(of: AnalysisOutcome.self) { group in
            var next = 0
            var outcomes: [AnalysisOutcome] = []
            outcomes.reserveCapacity(ids.count)

            while next < min(parallelism, ids.count) {
                let id = ids[next]
                next += 1
                group.addTask { await Self.analyze(id, source: source, analyzer: analyzer) }
            }
            while let outcome = await group.next() {
                outcomes.append(outcome)
                if next < ids.count {
                    let id = ids[next]
                    next += 1
                    group.addTask { await Self.analyze(id, source: source, analyzer: analyzer) }
                }
            }
            return outcomes
        }
    }

    private static func analyze(_ id: AssetID, source: any PhotoSource, analyzer: any ImageAnalyzer) async -> AnalysisOutcome {
        guard let thumbnail = await source.thumbnail(
            for: id,
            maxPixelSize: ScanPolicy.analysisThumbnailPixelSize,
            mode: .fit
        ) else {
            return AnalysisOutcome(id: id, analysis: nil)
        }
        let analysis = try? await analyzer.analyze(thumbnail)
        return AnalysisOutcome(id: id, analysis: analysis)
    }

    // MARK: Gesichter

    private func analyzeFaces(
        _ ids: [AssetID],
        version: Int,
        onUpdate: @escaping @Sendable (ScanUpdate) async -> Void
    ) async throws {
        let pending = try await index.pendingFaces(among: ids, version: version)
        guard !pending.isEmpty else { return }

        var done = 0
        for chunk in pending.chunks(of: Self.batchSize) {
            try Task.checkCancellation()
            await onUpdate(.progress(ScanProgress(stage: .faces, completed: done, total: pending.count)))
            let parallelism = try await AnalysisThrottle.waitForCapacity()
            let outcomes = await Self.faceBatch(Array(chunk), source: source, analyzer: analyzer, parallelism: parallelism)
            try await index.save(faces: outcomes, version: version)
            done += chunk.count
        }
    }

    private static func faceBatch(
        _ ids: [AssetID],
        source: any PhotoSource,
        analyzer: any ImageAnalyzer,
        parallelism: Int
    ) async -> [FaceOutcome] {
        await withTaskGroup(of: FaceOutcome.self) { group in
            var next = 0
            var outcomes: [FaceOutcome] = []

            while next < min(parallelism, ids.count) {
                let id = ids[next]
                next += 1
                group.addTask { await Self.faces(id, source: source, analyzer: analyzer) }
            }
            while let outcome = await group.next() {
                outcomes.append(outcome)
                if next < ids.count {
                    let id = ids[next]
                    next += 1
                    group.addTask { await Self.faces(id, source: source, analyzer: analyzer) }
                }
            }
            return outcomes
        }
    }

    private static func faces(_ id: AssetID, source: any PhotoSource, analyzer: any ImageAnalyzer) async -> FaceOutcome {
        guard let thumbnail = await source.thumbnail(
            for: id,
            maxPixelSize: ScanPolicy.analysisThumbnailPixelSize,
            mode: .fit
        ) else {
            return FaceOutcome(id: id, faces: nil)
        }
        let faces = try? await analyzer.analyzeFaces(thumbnail)
        return FaceOutcome(id: id, faces: faces ?? FaceSummary.none)
    }

    // MARK: Prüfsummen

    /// Prüfsummen der Kandidaten, aus dem Index oder frisch von lokalen Originalen.
    private func contentHashes(for ids: [AssetID]) async throws -> [AssetID: Data] {
        guard let hasher, !ids.isEmpty else { return [:] }
        var known = try await index.contentHashes(for: ids)
        var fresh: [AssetID: Data] = [:]
        for id in ids where known[id] == nil {
            try Task.checkCancellation()
            if let hash = await hasher.contentHash(for: id) {
                fresh[id] = hash
            }
        }
        if !fresh.isEmpty {
            try await index.save(contentHashes: fresh)
            known.merge(fresh) { stored, _ in stored }
        }
        return known
    }
}
