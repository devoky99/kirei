import Foundation

/// Exakte Duplikate in zwei Schritten.
///
/// 1. Kandidaten aus Metadaten: gleiche Art, gleiche Maße, gleiche Aufnahmezeit
///    auf die Millisekunde, gleiche Dauer, beide Live Photo oder beide nicht,
///    beide bearbeitet oder beide nicht. Serienbilder sind ausgenommen.
/// 2. Bestätigung über die Prüfsumme der lokalen Dateien. Nur bestätigte
///    Kopien bilden eine Gruppe und werden vorausgewählt.
///
/// Liegt ein Original nur in iCloud, gibt es keine Prüfsumme und keine
/// Duplikat-Gruppe. Fast gleiche Fotos findet dann „ähnlich“, mit Wahl des
/// besten Fotos und ohne Vorauswahl.
public enum DuplicateFinder {
    struct CandidateKey: Hashable {
        let kind: AssetKind
        let width: Int
        let height: Int
        let milliseconds: Int64
        let durationTenths: Int
        let isLivePhoto: Bool
        let hasAdjustments: Bool
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
                durationTenths: Int((record.duration * 10).rounded()),
                isLivePhoto: record.traits.contains(.livePhoto),
                hasAdjustments: record.hasAdjustments
            )
            buckets[key, default: []].append(record)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.id < $1.id } }
            .sorted { $0[0].id < $1[0].id }
    }

    /// Bestätigt Kandidaten über gleiche Prüfsummen und baut Gruppen.
    public static func resolve(
        candidates: [[AssetRecord]],
        hashes: [AssetID: Data],
        settings: SuggestionSettings
    ) -> [SuggestionGroup] {
        candidates.flatMap { bucket -> [SuggestionGroup] in
            var byHash: [Data: [AssetRecord]] = [:]
            for record in bucket {
                if let hash = hashes[record.id] {
                    byHash[hash, default: []].append(record)
                }
            }
            return byHash.values
                .filter { $0.count > 1 }
                .sorted { $0[0].id < $1[0].id }
                .compactMap { makeGroup($0, settings: settings) }
        }
    }

    static func makeGroup(_ members: [AssetRecord], settings: SuggestionSettings) -> SuggestionGroup? {
        // Behalten: geschützt vor ungeschützt, dann stabil nach Kennung.
        let keep = members.min { a, b in
            let protectedA = settings.protection.reason(for: a) != nil
            let protectedB = settings.protection.reason(for: b) != nil
            if protectedA != protectedB { return protectedA }
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
            } else {
                items.append(SuggestionItem(
                    assetID: member.id,
                    role: .remove,
                    reasons: [.exactCopy],
                    isPreselected: true,
                    estimatedBytes: bytes
                ))
            }
        }

        guard items.contains(where: { $0.role == .remove }) else { return nil }
        return SuggestionGroup(
            id: SuggestionGroup.makeID(.exactDuplicates, members.map(\.id)),
            category: .exactDuplicates,
            items: items
        )
    }
}
