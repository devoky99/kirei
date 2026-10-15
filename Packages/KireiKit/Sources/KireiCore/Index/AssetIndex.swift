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

/// Wo das seitenweise Lesen weitermacht: nach diesem Aufnahmedatum.
///
/// Geblättert wird nur nach Datum, weil die Datenbank Zahlen in Kennungen
/// „natürlich“ sortiert, beim Vergleichen aber Zeichen für Zeichen vorgeht.
/// Fotos mit gleichem Datum kommen immer gemeinsam auf eine Seite.
public struct IndexCursor: Sendable, Equatable {
    public let sortDate: Date

    public init(sortDate: Date) {
        self.sortDate = sortDate
    }
}

/// Eine Seite analysierter Fotos und wo es weitergeht.
public struct AnalyzedPage: Sendable {
    public let photos: [AnalyzedPhoto]
    /// `nil`, wenn alles gelesen ist. Eine Seite kann leer sein und trotzdem weitergehen.
    public let next: IndexCursor?
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
    /// Arbeitet seitenweise mit je einem frischen Kontext und lädt nur die
    /// Felder, die verglichen werden. So bleibt der Speicher auch bei 100.000
    /// Fotos klein, beim ersten wie bei jedem weiteren Scan.
    @discardableResult
    public func sync(_ records: [AssetRecord]) throws -> IndexSyncResult {
        var remaining: [String: AssetRecord] = [:]
        remaining.reserveCapacity(records.count)
        for record in records where remaining[record.id.rawValue] == nil {
            remaining[record.id.rawValue] = record
        }
        var result = IndexSyncResult(inserted: 0, updated: 0, removed: 0)

        // 1. Vorhandene Einträge seitenweise nach Datum abgleichen. Ein Eintrag,
        //    dessen Datum sich ändert, kann später noch einmal auftauchen und
        //    wird dann übersprungen.
        var processed = Set<String>()
        var cursor: Date?
        while true {
            let lastDate: Date? = try withContext { context in
                var page = try Self.datePage(in: context, after: cursor, limit: Self.saveChunk)
                guard let lastDate = page.last?.sortDate else { return nil }
                page += try Self.sameDate(lastDate, in: context)

                for entry in page {
                    guard processed.insert(entry.assetID).inserted else { continue }
                    if let record = remaining.removeValue(forKey: entry.assetID) {
                        let dateChanged = entry.sortDate != (record.creationDate ?? .distantPast)
                        if entry.modificationDate != record.modificationDate
                            || entry.isAnalyzable != record.isAnalyzable
                            || dateChanged {
                            entry.reset(with: record)
                            result.updated += 1
                        }
                    } else {
                        context.delete(entry)
                        result.removed += 1
                    }
                }
                try context.save()
                return lastDate
            }
            guard let lastDate else { break }
            cursor = lastDate
        }

        // 2. Neue Einträge in Paketen anlegen.
        for chunk in Array(remaining.values).chunks(of: Self.saveChunk) {
            try withContext { context in
                for record in chunk {
                    context.insert(IndexedAsset(record: record))
                }
                try context.save()
            }
            result.inserted += chunk.count
        }
        return result
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

    /// Analysierte Fotos, älteste zuerst, seitenweise nach Datum.
    ///
    /// Eine Seite enthält etwa `limit` Fotos und immer alle Fotos mit dem
    /// Datum des letzten Eintrags. So geht beim Weiterlesen keines verloren.
    public func analyzedPhotos(version: Int, after cursor: IndexCursor?, limit: Int) throws -> AnalyzedPage {
        try withContext { context in
            var page = try Self.datePage(in: context, after: cursor?.sortDate, limit: limit)
            guard let lastDate = page.last?.sortDate else { return AnalyzedPage(photos: [], next: nil) }
            page += try Self.sameDate(lastDate, in: context)

            var seen = Set<String>()
            let photos = page
                .filter { entry in
                    seen.insert(entry.assetID).inserted
                        && entry.isAnalyzable
                        && entry.analysisVersion >= version
                        && !entry.analysisUnavailable
                }
                .sorted { ($0.sortDate, $0.assetID) < ($1.sortDate, $1.assetID) }
                .map { $0.analyzedPhoto(faceVersion: version) }
            return AnalyzedPage(photos: photos, next: IndexCursor(sortDate: lastDate))
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

    /// Bis zu `limit` Einträge nach `after`, aufsteigend nach Datum.
    private static func datePage(in context: ModelContext, after: Date?, limit: Int) throws -> [IndexedAsset] {
        var descriptor: FetchDescriptor<IndexedAsset>
        if let after {
            descriptor = FetchDescriptor<IndexedAsset>(
                predicate: #Predicate<IndexedAsset> { $0.sortDate > after },
                sortBy: [SortDescriptor(\.sortDate)]
            )
        } else {
            descriptor = FetchDescriptor<IndexedAsset>(sortBy: [SortDescriptor(\.sortDate)])
        }
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Alle Einträge mit genau diesem Datum.
    private static func sameDate(_ date: Date, in context: ModelContext) throws -> [IndexedAsset] {
        try context.fetch(FetchDescriptor<IndexedAsset>(
            predicate: #Predicate<IndexedAsset> { $0.sortDate == date }
        ))
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
