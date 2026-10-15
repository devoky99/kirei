import Foundation
import SwiftData

/// Ergebnis der Analyse eines Fotos. `analysis == nil` heißt: kein lokales Vorschaubild.
public struct AnalysisOutcome: Sendable, Equatable {
    public let id: AssetID
    public let analysis: ImageAnalysis?

    public init(id: AssetID, analysis: ImageAnalysis?) {
        self.id = id
        self.analysis = analysis
    }
}

/// Ergebnis der Gesichtsanalyse. `faces == nil` heißt: kein lokales Vorschaubild.
public struct FaceOutcome: Sendable, Equatable {
    public let id: AssetID
    public let faces: FaceSummary?

    public init(id: AssetID, faces: FaceSummary?) {
        self.id = id
        self.faces = faces
    }
}

/// Wo das seitenweise Lesen weitermacht: Datum und Kennung des letzten Eintrags.
public struct IndexCursor: Sendable, Equatable {
    public let sortDate: Date
    public let assetID: String

    public init(after photo: AnalyzedPhoto) {
        sortDate = photo.date ?? .distantPast
        assetID = photo.id.rawValue
    }
}

/// Was der Abgleich mit der Mediathek verändert hat.
public struct IndexSyncResult: Sendable, Equatable {
    public var inserted: Int
    public var updated: Int
    public var removed: Int
}

/// Stand der Bildanalyse.
public struct AnalysisCounts: Sendable, Equatable {
    /// Fotos, die analysiert werden sollen.
    public var analyzable: Int
    /// Davon erledigt, auch die ohne lokales Vorschaubild.
    public var processed: Int
    /// Davon ohne lokales Vorschaubild, etwa nur in iCloud.
    public var unavailable: Int

    public var pending: Int { max(0, analyzable - processed) }
}

/// Der lokale Index in SwiftData. Merkt sich pro Foto die Analyse, damit
/// nach dem ersten Scan nur Neues und Geändertes gerechnet wird.
@ModelActor
public actor AssetIndex {
    /// Wie viele Kennungen ein Filter höchstens auf einmal prüft.
    static let lookupChunk = 400
    /// Nach so vielen Änderungen wird zwischengespeichert.
    static let saveChunk = 2_000

    // MARK: Anlegen

    /// Für Tests und den Prüfstand: nur im Arbeitsspeicher.
    public static func inMemory() throws -> AssetIndex {
        let configuration = ModelConfiguration(
            UUID().uuidString,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: IndexedAsset.self, configurations: configuration)
        return AssetIndex(modelContainer: container)
    }

    /// Ablage in Kireis eigenem Ordner, ohne Backup und ohne CloudKit.
    public static func standard() throws -> AssetIndex {
        try onDisk(directory: KireiStorage.directory())
    }

    /// Ablage in einem bestimmten Ordner, etwa für Lasttests im Prüfstand.
    public static func onDisk(directory: URL) throws -> AssetIndex {
        let configuration = ModelConfiguration(
            url: directory.appending(path: "index.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: IndexedAsset.self, configurations: configuration)
        return AssetIndex(modelContainer: container)
    }

    // MARK: Abgleich mit der Mediathek

    /// Neue Einträge anlegen, geänderte zurücksetzen, verschwundene löschen.
    ///
    /// Lädt nur die Felder, die verglichen werden, nicht die Merkmalsvektoren.
    /// Speichert in Paketen, damit auch 100.000 neue Einträge wenig Speicher brauchen.
    @discardableResult
    public func sync(_ records: [AssetRecord]) throws -> IndexSyncResult {
        return try withContext { context in
            var descriptor = FetchDescriptor<IndexedAsset>()
            descriptor.propertiesToFetch = [\.assetID, \.sortDate, \.modificationDate, \.isAnalyzable]
            let existing = try context.fetch(descriptor)
            var byID: [String: IndexedAsset] = [:]
            byID.reserveCapacity(existing.count)
            for entry in existing {
                byID[entry.assetID] = entry
            }

            var seen = Set<String>()
            var result = IndexSyncResult(inserted: 0, updated: 0, removed: 0)
            var pending = 0
            for record in records {
                let key = record.id.rawValue
                guard seen.insert(key).inserted else { continue }
                if let entry = byID[key] {
                    let dateChanged = entry.sortDate != (record.creationDate ?? .distantPast)
                    if entry.modificationDate != record.modificationDate
                        || entry.isAnalyzable != record.isAnalyzable
                        || dateChanged {
                        entry.reset(with: record)
                        result.updated += 1
                        pending += 1
                    }
                } else {
                    context.insert(IndexedAsset(record: record))
                    result.inserted += 1
                    pending += 1
                }
                if pending >= Self.saveChunk {
                    try context.save()
                    pending = 0
                }
            }

            for entry in existing where !seen.contains(entry.assetID) {
                context.delete(entry)
                result.removed += 1
            }

            try context.save()
            return result
        }
    }

    /// Fotos ohne lokales Vorschaubild beim nächsten Durchlauf erneut versuchen.
    /// Etwa wenn iCloud inzwischen ein Vorschaubild geladen hat.
    public func retryUnavailable() throws {
        try withContext { context in
            let descriptor = FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { $0.analysisUnavailable == true }
            )
            for entry in try context.fetch(descriptor) {
                entry.analysisVersion = 0
                entry.analysisUnavailable = false
            }
            try context.save()
        }
    }

    // MARK: Bildanalyse

    /// Fotos ohne aktuelle Analyse, neueste zuerst.
    public func pendingAnalysis(version: Int, limit: Int) throws -> [AssetID] {
        return try withContext { context in
            var descriptor = FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { $0.isAnalyzable == true && $0.analysisVersion < version },
                sortBy: [SortDescriptor(\.sortDate, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map { AssetID($0.assetID) }
        }
    }

    public func save(analyses outcomes: [AnalysisOutcome], version: Int) throws {
        try withContext { context in
            let entries = try entries(for: outcomes.map(\.id), in: context)
            for outcome in outcomes {
                guard let entry = entries[outcome.id.rawValue] else { continue }
                entry.analysisVersion = version
                if let analysis = outcome.analysis {
                    entry.analysisUnavailable = false
                    entry.featurePrintData = analysis.featurePrint?.data
                    entry.aestheticScore = analysis.aestheticScore.map(Double.init)
                    entry.isUtility = analysis.isUtility
                    entry.sharpness = analysis.sharpness
                } else {
                    entry.analysisUnavailable = true
                    entry.featurePrintData = nil
                    entry.aestheticScore = nil
                    entry.isUtility = false
                    entry.sharpness = 0
                }
            }
            try context.save()
        }
    }

    public func analysisCounts(version: Int) throws -> AnalysisCounts {
        return try withContext { context in
            let analyzable = try context.fetchCount(FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { $0.isAnalyzable == true }
            ))
            let processed = try context.fetchCount(FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { $0.isAnalyzable == true && $0.analysisVersion >= version }
            ))
            let unavailable = try context.fetchCount(FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> {
                    $0.isAnalyzable == true && $0.analysisVersion >= version && $0.analysisUnavailable == true
                }
            ))
            return AnalysisCounts(analyzable: analyzable, processed: processed, unavailable: unavailable)
        }
    }

    /// Analysierte Fotos, älteste zuerst, seitenweise.
    ///
    /// Liest ab dem letzten Eintrag der vorigen Seite weiter statt mit wachsendem
    /// Versatz. So bleibt jede Seite gleich schnell, auch bei 100.000 Fotos.
    public func analyzedPhotos(version: Int, after cursor: IndexCursor?, limit: Int) throws -> [AnalyzedPhoto] {
        return try withContext { context in
            var descriptor: FetchDescriptor<IndexedAsset>
            if let cursor {
                let date = cursor.sortDate
                let id = cursor.assetID
                descriptor = FetchDescriptor<IndexedAsset>(
                    predicate: #Predicate<IndexedAsset> {
                        $0.isAnalyzable == true
                            && $0.analysisVersion >= version
                            && $0.analysisUnavailable == false
                            && ($0.sortDate > date || ($0.sortDate == date && $0.assetID > id))
                    },
                    sortBy: [SortDescriptor(\.sortDate), SortDescriptor(\.assetID)]
                )
            } else {
                descriptor = FetchDescriptor<IndexedAsset>(
                    predicate: #Predicate<IndexedAsset> {
                        $0.isAnalyzable == true
                            && $0.analysisVersion >= version
                            && $0.analysisUnavailable == false
                    },
                    sortBy: [SortDescriptor(\.sortDate), SortDescriptor(\.assetID)]
                )
            }
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map { $0.analyzedPhoto(faceVersion: version) }
        }
    }

    public func featurePrints(for ids: [AssetID]) throws -> [AssetID: FeaturePrint] {
        return try withContext { context in
            var result: [AssetID: FeaturePrint] = [:]
            for (key, entry) in try entries(for: ids, in: context) {
                if let data = entry.featurePrintData, let print = FeaturePrint(data: data) {
                    result[AssetID(key)] = print
                }
            }
            return result
        }
    }

    // MARK: Gesichter

    public func pendingFaces(among ids: [AssetID], version: Int) throws -> [AssetID] {
        return try withContext { context in
            try entries(for: ids, in: context).values
                .filter { $0.faceVersion < version }
                .map { AssetID($0.assetID) }
                .sorted()
        }
    }

    public func save(faces outcomes: [FaceOutcome], version: Int) throws {
        try withContext { context in
            let entries = try entries(for: outcomes.map(\.id), in: context)
            for outcome in outcomes {
                // Ohne Vorschaubild bleibt der Eintrag offen und wird beim nächsten Scan versucht.
                guard let entry = entries[outcome.id.rawValue], let faces = outcome.faces else { continue }
                entry.faceVersion = version
                entry.faceCount = faces.faceCount
                entry.minEyeOpenness = faces.minEyeOpenness
                entry.faceQuality = faces.meanCaptureQuality
            }
            try context.save()
        }
    }

    public func faces(for ids: [AssetID], version: Int) throws -> [AssetID: FaceSummary] {
        return try withContext { context in
            var result: [AssetID: FaceSummary] = [:]
            for (key, entry) in try entries(for: ids, in: context) where entry.faceVersion >= version {
                result[AssetID(key)] = FaceSummary(
                    faceCount: entry.faceCount,
                    minEyeOpenness: entry.minEyeOpenness,
                    meanCaptureQuality: entry.faceQuality
                )
            }
            return result
        }
    }

    // MARK: Prüfsummen

    public func contentHashes(for ids: [AssetID]) throws -> [AssetID: Data] {
        return try withContext { context in
            var result: [AssetID: Data] = [:]
            for (key, entry) in try entries(for: ids, in: context) {
                if let hash = entry.contentHash {
                    result[AssetID(key)] = hash
                }
            }
            return result
        }
    }

    public func save(contentHashes: [AssetID: Data]) throws {
        try withContext { context in
            let entries = try entries(for: Array(contentHashes.keys), in: context)
            for (id, hash) in contentHashes {
                entries[id.rawValue]?.contentHash = hash
            }
            try context.save()
        }
    }

    // MARK: Hilfen

    /// Ein frischer Kontext pro Arbeitsschritt. So hält der Index keine
    /// gelesenen Einträge über den Schritt hinaus fest und der Speicher wächst
    /// nicht von Scan zu Scan.
    private func withContext<Result>(_ body: (ModelContext) throws -> Result) rethrows -> Result {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return try body(context)
    }

    private func entries(for ids: [AssetID], in context: ModelContext) throws -> [String: IndexedAsset] {
        var result: [String: IndexedAsset] = [:]
        let keys = ids.map(\.rawValue)
        for start in stride(from: 0, to: keys.count, by: Self.lookupChunk) {
            let chunk = Array(keys[start..<min(start + Self.lookupChunk, keys.count)])
            let descriptor = FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { chunk.contains($0.assetID) }
            )
            for entry in try context.fetch(descriptor) {
                result[entry.assetID] = entry
            }
        }
        return result
    }
}
