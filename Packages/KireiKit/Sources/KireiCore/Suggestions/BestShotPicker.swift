import Foundation

/// Ein Mitglied einer Gruppe fast gleicher Fotos, mit allem, was zur Wahl zählt.
public struct GroupMember: Sendable {
    public let record: AssetRecord
    public let photo: AnalyzedPhoto
    public let faces: FaceSummary?

    public init(record: AssetRecord, photo: AnalyzedPhoto, faces: FaceSummary?) {
        self.record = record
        self.photo = photo
        self.faces = faces
    }
}

/// Wählt in einer Gruppe das beste Foto und begründet jeden Vorschlag.
///
/// Reihenfolge: geschützte Fotos zuerst, dann offene Augen, dann Qualität
/// aus Ästhetik-Score, Schärfe und Gesichtsqualität. Bei Gleichstand das
/// zuerst aufgenommene. Nichts wird vorausgewählt.
public enum BestShotPicker {
    public static func makeGroup(_ members: [GroupMember], settings: SuggestionSettings) -> SuggestionGroup? {
        guard members.count > 1 else { return nil }

        let maxSharpness = members.map(\.photo.sharpness).max() ?? 0

        func eyesClosed(_ member: GroupMember) -> Bool {
            guard let openness = member.faces?.minEyeOpenness else { return false }
            return openness < settings.eyesClosedOpenness
        }

        func quality(_ member: GroupMember) -> Double {
            let aesthetic = Double(member.photo.aestheticScore ?? 0)
            let sharpness = maxSharpness > 0 ? member.photo.sharpness / maxSharpness : 0
            let face = member.faces?.meanCaptureQuality ?? 0
            return aesthetic + 0.5 * sharpness + 0.25 * face
        }

        func isProtected(_ member: GroupMember) -> Bool {
            settings.protection.reason(for: member.record) != nil
        }

        func ranksLower(_ a: GroupMember, _ b: GroupMember) -> Bool {
            if isProtected(a) != isProtected(b) { return !isProtected(a) }
            if eyesClosed(a) != eyesClosed(b) { return eyesClosed(a) }
            let qualityA = quality(a)
            let qualityB = quality(b)
            if qualityA != qualityB { return qualityA < qualityB }
            let dateA = a.photo.date ?? .distantFuture
            let dateB = b.photo.date ?? .distantFuture
            if dateA != dateB { return dateA > dateB }
            return a.record.id > b.record.id
        }

        guard let keep = members.max(by: ranksLower) else { return nil }

        var keepReasons: [SuggestionReason] = [.bestOfGroup]
        if maxSharpness > 0 && keep.photo.sharpness >= maxSharpness {
            keepReasons.append(.sharpest)
        }
        let othersClosed = members.contains { $0.record.id != keep.record.id && eyesClosed($0) }
        if othersClosed && !eyesClosed(keep) {
            keepReasons.append(.eyesOpen)
        }
        if let protection = settings.protection.reason(for: keep.record) {
            keepReasons.append(.protected(protection))
        }

        var items = [SuggestionItem(
            assetID: keep.record.id,
            role: .keep,
            reasons: keepReasons,
            estimatedBytes: SizeEstimator.estimatedBytes(for: keep.record)
        )]

        let others = members
            .filter { $0.record.id != keep.record.id }
            .sorted { ($0.photo.date ?? .distantFuture) < ($1.photo.date ?? .distantFuture) }

        for member in others {
            let bytes = SizeEstimator.estimatedBytes(for: member.record)
            if let protection = settings.protection.reason(for: member.record) {
                items.append(SuggestionItem(assetID: member.record.id, role: .keep, reasons: [.protected(protection)], estimatedBytes: bytes))
                continue
            }
            var reasons: [SuggestionReason] = [.nearlyIdentical]
            if eyesClosed(member) && !eyesClosed(keep) {
                reasons.append(.eyesClosed)
            }
            if keep.photo.sharpness > 0 && member.photo.sharpness < keep.photo.sharpness * settings.lessSharpFactor {
                reasons.append(.lessSharp)
            }
            items.append(SuggestionItem(assetID: member.record.id, role: .remove, reasons: reasons, estimatedBytes: bytes))
        }

        guard items.contains(where: { $0.role == .remove }) else { return nil }
        return SuggestionGroup(
            id: SuggestionGroup.makeID(.similar, members.map(\.record.id)),
            category: .similar,
            items: items
        )
    }
}
