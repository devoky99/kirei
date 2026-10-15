import Foundation

/// Exakte Duplikate in zwei Schritten.
///
/// 1. Kandidaten aus Metadaten: gleiche Art, gleiche Maße, gleiche Aufnahmezeit
///    auf die Millisekunde, gleiche Dauer. Serienbilder sind ausgenommen.
/// 2. Bestätigung über die Prüfsumme des lokalen Originals. Nur bestätigte
///    Kopien werden vorausgewählt. Liegt ein Original nur in iCloud, gilt ein
///    Kandidat bei fast identischem Merkmalsvektor als „wahrscheinlich eine
///    Kopie“ und wird nicht vorausgewählt.
public enum DuplicateFinder {
    struct CandidateKey: Hashable {
        let kind: AssetKind
        let width: Int
        let height: Int
        let milliseconds: Int64
        let durationTenths: Int
    }

    /// Gruppen von Einträgen, die Kopien sein könnten.
    public static func candidates(in records: [AssetRecord]) -> [[AssetRecord]] {
        var buckets: [CandidateKey: [AssetRecord]] = [:]
        for record in records where record.burstIdentifier == nil && record.kind != .other {
            guard let date = record.creationDate else { continue }
            let key = CandidateKey(
                kind: record.kind,
                width: record.pixelWidth,
                height: record.pixelHeight,
                milliseconds: Int64((date.timeIntervalSinceReferenceDate * 1000).rounded()),
                durationTenths: Int((record.duration * 10).rounded())
            )
            buckets[key, default: []].append(record)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.id < $1.id } }
            .sorted { $0[0].id < $1[0].id }
    }

    /// Bestätigt Kandidaten und baut Gruppen.
    public static func resolve(
        candidates: [[AssetRecord]],
        hashes: [AssetID: Data],
        prints: [AssetID: FeaturePrint],
        settings: SuggestionSettings
    ) -> [SuggestionGroup] {
        candidates.flatMap { bucket in
            components(of: bucket, hashes: hashes, prints: prints, settings: settings)
                .compactMap { makeGroup($0, hashes: hashes, settings: settings) }
        }
    }

    /// Verbindet Einträge mit gleicher Prüfsumme oder, ohne Prüfsumme, mit fast
    /// gleichem Merkmalsvektor. Verschiedene Prüfsummen landen nie in einer Gruppe.
    static func components(
        of bucket: [AssetRecord],
        hashes: [AssetID: Data],
        prints: [AssetID: FeaturePrint],
        settings: SuggestionSettings
    ) -> [[AssetRecord]] {
        var parent = Array(bucket.indices)
        var hashSets: [Set<Data>] = bucket.map { record in
            hashes[record.id].map { [$0] } ?? []
        }

        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                current = parent[current]
            }
            return current
        }

        func join(_ a: Int, _ b: Int) {
            let rootA = root(a)
            let rootB = root(b)
            guard rootA != rootB else { return }
            let merged = hashSets[rootA].union(hashSets[rootB])
            guard merged.count <= 1 else { return }
            parent[rootB] = rootA
            hashSets[rootA] = merged
        }

        for i in bucket.indices {
            for j in bucket.indices where j > i {
                let first = bucket[i].id
                let second = bucket[j].id
                if let hashA = hashes[first], let hashB = hashes[second] {
                    if hashA == hashB { join(i, j) }
                } else if let printA = prints[first], let printB = prints[second],
                          printA.distance(to: printB) <= settings.probableCopyDistance {
                    join(i, j)
                }
            }
        }

        var groups: [Int: [AssetRecord]] = [:]
        for index in bucket.indices {
            groups[root(index), default: []].append(bucket[index])
        }
        return groups.values
            .filter { $0.count > 1 }
            .sorted { $0[0].id < $1[0].id }
    }

    static func makeGroup(
        _ members: [AssetRecord],
        hashes: [AssetID: Data],
        settings: SuggestionSettings
    ) -> SuggestionGroup? {
        // Behalten: geschützt vor ungeschützt, mit Prüfsumme vor ohne, dann stabil nach Kennung.
        let keep = members.min { a, b in
            let protectedA = settings.protection.reason(for: a) != nil
            let protectedB = settings.protection.reason(for: b) != nil
            if protectedA != protectedB { return protectedA }
            let hashedA = hashes[a.id] != nil
            let hashedB = hashes[b.id] != nil
            if hashedA != hashedB { return hashedA }
            return a.id < b.id
        }
        guard let keep else { return nil }

        var keepReasons: [SuggestionReason] = [.original]
        if let protection = settings.protection.reason(for: keep) {
            keepReasons.append(.protected(protection))
        }
        var items = [SuggestionItem(
            assetID: keep.id,
            role: .keep,
            reasons: keepReasons,
            estimatedBytes: SizeEstimator.estimatedBytes(for: keep)
        )]

        for member in members where member.id != keep.id {
            let bytes = SizeEstimator.estimatedBytes(for: member)
            if let protection = settings.protection.reason(for: member) {
                items.append(SuggestionItem(assetID: member.id, role: .keep, reasons: [.protected(protection)], estimatedBytes: bytes))
                continue
            }
            let confirmed = hashes[member.id] != nil && hashes[member.id] == hashes[keep.id]
            items.append(SuggestionItem(
                assetID: member.id,
                role: .remove,
                reasons: [confirmed ? .exactCopy : .probableCopy],
                isPreselected: confirmed,
                estimatedBytes: bytes
            ))
        }

        guard items.contains(where: { $0.role == .remove }) else { return nil }
        return SuggestionGroup(
            id: SuggestionGroup.makeID(.exactDuplicates, members.map(\.id)),
            category: .exactDuplicates,
            items: items
        )
    }
}
