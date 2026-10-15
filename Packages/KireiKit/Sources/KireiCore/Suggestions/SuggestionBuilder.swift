import Foundation

/// Vorschläge, die ohne Bildanalyse feststehen, und die Gruppe „unscharf“.
///
/// Bildschirmfotos, Bildschirmaufnahmen, Serien und große Videos kommen nur
/// aus Metadaten und stehen deshalb nach Sekunden bereit.
public enum SuggestionBuilder {
    public static func metadataGroups(
        records: [AssetRecord],
        settings: SuggestionSettings,
        now: Date
    ) -> [SuggestionGroup] {
        var groups = burstGroups(records: records, settings: settings)
        if let screenshots = screenshotGroup(records: records, settings: settings, now: now) {
            groups.append(screenshots)
        }
        if let recordings = screenRecordingGroup(records: records, settings: settings) {
            groups.append(recordings)
        }
        if let videos = largeVideoGroup(records: records, settings: settings) {
            groups.append(videos)
        }
        return groups
    }

    // MARK: Serien

    /// Behalten wird, was in Fotos sichtbar oder ausgewählt ist. Ohne eigene
    /// Auswahl bleiben auch die Bilder, die die Kamera als gut markiert hat.
    public static func burstGroups(records: [AssetRecord], settings: SuggestionSettings) -> [SuggestionGroup] {
        var bursts: [String: [AssetRecord]] = [:]
        for record in records {
            if let burst = record.burstIdentifier {
                bursts[burst, default: []].append(record)
            }
        }

        return bursts.keys.sorted().compactMap { key -> SuggestionGroup? in
            guard let members = bursts[key], members.count > 1 else { return nil }
            let sorted = members.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            let hasUserPick = sorted.contains { $0.traits.contains(.burstUserPick) }

            func isSelected(_ record: AssetRecord) -> Bool {
                if record.traits.contains(.burstRepresentative) || record.traits.contains(.burstUserPick) {
                    return true
                }
                return !hasUserPick && record.traits.contains(.burstAutoPick)
            }

            var selectedIDs = Set(sorted.filter(isSelected).map(\.id))
            if selectedIDs.isEmpty, let first = sorted.first {
                selectedIDs.insert(first.id)
            }

            var items: [SuggestionItem] = []
            for record in sorted {
                let bytes = SizeEstimator.estimatedBytes(for: record)
                let protection = settings.protection.reason(for: record)
                if selectedIDs.contains(record.id) {
                    var reasons: [SuggestionReason] = [.burstSelection]
                    if let protection { reasons.append(.protected(protection)) }
                    items.append(SuggestionItem(assetID: record.id, role: .keep, reasons: reasons, estimatedBytes: bytes))
                } else if let protection {
                    items.append(SuggestionItem(assetID: record.id, role: .keep, reasons: [.protected(protection)], estimatedBytes: bytes))
                } else {
                    items.append(SuggestionItem(assetID: record.id, role: .remove, reasons: [.unselectedBurstFrame], estimatedBytes: bytes))
                }
            }

            guard items.contains(where: { $0.role == .remove }) else { return nil }
            return SuggestionGroup(id: "bursts|\(key)", category: .bursts, items: items)
        }
    }

    // MARK: Bildschirmfotos und -aufnahmen

    public static func screenshotGroup(
        records: [AssetRecord],
        settings: SuggestionSettings,
        now: Date
    ) -> SuggestionGroup? {
        let items: [SuggestionItem] = records
            .filter { $0.isScreenshot && settings.protection.reason(for: $0) == nil }
            .compactMap { record -> (AssetRecord, Int)? in
                guard let date = record.creationDate else { return nil }
                let days = Int(now.timeIntervalSince(date) / 86_400)
                return days >= settings.screenshotMinAgeDays ? (record, days) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map { record, days in
                SuggestionItem(
                    assetID: record.id,
                    role: .remove,
                    reasons: [.screenshot(ageInDays: days)],
                    estimatedBytes: SizeEstimator.estimatedBytes(for: record)
                )
            }
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(id: "screenshots", category: .screenshots, items: items)
    }

    public static func screenRecordingGroup(records: [AssetRecord], settings: SuggestionSettings) -> SuggestionGroup? {
        let items: [SuggestionItem] = records
            .filter { $0.isScreenRecording && settings.protection.reason(for: $0) == nil }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            .map { record in
                SuggestionItem(
                    assetID: record.id,
                    role: .remove,
                    reasons: [.screenRecording(seconds: Int(record.duration.rounded()))],
                    estimatedBytes: SizeEstimator.estimatedBytes(for: record)
                )
            }
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(id: "screenRecordings", category: .screenRecordings, items: items)
    }

    // MARK: Große Videos

    public static func largeVideoGroup(records: [AssetRecord], settings: SuggestionSettings) -> SuggestionGroup? {
        let items: [SuggestionItem] = records
            .filter { $0.kind == .video && !$0.isScreenRecording && settings.protection.reason(for: $0) == nil }
            .map { ($0, SizeEstimator.estimatedBytes(for: $0)) }
            .filter { $0.1 >= settings.largeVideoMinBytes }
            .sorted { $0.1 > $1.1 }
            .map { record, bytes in
                SuggestionItem(
                    assetID: record.id,
                    role: .remove,
                    reasons: [.largeVideo(estimatedBytes: bytes)],
                    estimatedBytes: bytes
                )
            }
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(id: "largeVideos", category: .largeVideos, items: items)
    }

    // MARK: Unscharf

    /// Unscharf nur, wenn Ästhetik-Score und eigene Schärfemessung beide niedrig sind.
    /// Gebrauchsbilder wie Belege zählen nie.
    public static func isBlurry(_ photo: AnalyzedPhoto, settings: SuggestionSettings) -> Bool {
        guard !photo.isUtility, let score = photo.aestheticScore else { return false }
        return score <= settings.blurAestheticMax && photo.sharpness <= settings.blurSharpnessMax
    }

    public static func blurryGroup(
        photos: [AnalyzedPhoto],
        records: [AssetID: AssetRecord],
        settings: SuggestionSettings
    ) -> SuggestionGroup? {
        let items: [SuggestionItem] = photos
            .filter { isBlurry($0, settings: settings) }
            .compactMap { photo -> SuggestionItem? in
                guard let record = records[photo.id], settings.protection.reason(for: record) == nil else { return nil }
                return SuggestionItem(
                    assetID: photo.id,
                    role: .remove,
                    reasons: [.blurry],
                    estimatedBytes: SizeEstimator.estimatedBytes(for: record)
                )
            }
        guard !items.isEmpty else { return nil }
        // Neueste zuerst.
        return SuggestionGroup(id: "blurry", category: .blurry, items: Array(items.reversed()))
    }

    /// Sortiert Gruppen nach Kategorie, innerhalb einer Kategorie stabil.
    public static func ordered(_ groups: [SuggestionGroup]) -> [SuggestionGroup] {
        let order = Dictionary(uniqueKeysWithValues: SuggestionCategory.allCases.enumerated().map { ($1, $0) })
        return groups.enumerated()
            .sorted { lhs, rhs in
                let left = order[lhs.element.category] ?? 0
                let right = order[rhs.element.category] ?? 0
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
