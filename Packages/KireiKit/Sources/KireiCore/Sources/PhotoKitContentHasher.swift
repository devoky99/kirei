#if canImport(Photos)
import CryptoKit
import Foundation
import Photos

/// Prüfsumme (SHA-256) für exakte Duplikate.
///
/// Umfasst das Original, das Video eines Live Photos und die Bearbeitung.
/// Zwei Einträge mit gleichem Original, aber verschiedener Bearbeitung
/// gelten so nicht als Kopien. Gelesen wird nur, was auf dem Gerät liegt.
/// Fehlt ein Teil, weil er nur in iCloud liegt, gibt es keine Prüfsumme und
/// das Duplikat wird nicht vorgeschlagen. Nur für Kandidaten mit gleichen
/// Maßen und gleicher Aufnahmezeit.
public struct PhotoKitContentHasher: ContentHasher {
    /// Diese Teile bestimmen, ob zwei Einträge wirklich gleich sind.
    static let relevantTypes: [PHAssetResourceType] = [.photo, .video, .pairedVideo, .adjustmentData]

    public init() {}

    public func contentHash(for id: AssetID) async -> Data? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id.rawValue], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
            .filter { Self.relevantTypes.contains($0.type) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
        guard resources.contains(where: { $0.type == .photo || $0.type == .video }) else { return nil }

        let accumulator = HashAccumulator()
        for resource in resources {
            // Trennzeichen pro Teil, damit verschiedene Aufteilungen nie gleich aussehen.
            accumulator.update(with: Data("kirei:\(resource.type.rawValue):".utf8))
            guard await Self.feed(resource, into: accumulator) else { return nil }
        }
        return accumulator.finalize()
    }

    /// Liest einen Teil in die Prüfsumme. `false`, wenn er nicht lokal liegt.
    private static func feed(_ resource: PHAssetResource, into accumulator: HashAccumulator) async -> Bool {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = ScanPolicy.allowsNetworkAccess

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    accumulator.update(with: data)
                },
                completionHandler: { error in
                    continuation.resume(returning: error == nil)
                }
            )
        }
    }
}

/// Sammelt die Datenstücke, die PhotoKit nacheinander liefert.
final class HashAccumulator: @unchecked Sendable {
    // Zugriff nur unter der Sperre.
    private let lock = NSLock()
    private var hasher = SHA256()

    func update(with data: Data) {
        lock.withLock { hasher.update(data: data) }
    }

    func finalize() -> Data {
        lock.withLock { Data(hasher.finalize()) }
    }
}
#endif
