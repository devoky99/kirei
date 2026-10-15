#if canImport(Photos)
import CryptoKit
import Foundation
import Photos

/// Prüfsumme (SHA-256) des Originals für exakte Duplikate.
///
/// Liest das Original nur, wenn es auf dem Gerät liegt. Liegt es nur in
/// iCloud, gibt es keine Prüfsumme und das Duplikat wird nicht vorausgewählt.
/// Nur für Kandidaten mit gleichen Maßen und gleicher Aufnahmezeit.
public struct PhotoKitContentHasher: ContentHasher {
    public init() {}

    public func contentHash(for id: AssetID) async -> Data? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id.rawValue], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let original = resources.first(where: { $0.type == .photo || $0.type == .video }) else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = ScanPolicy.allowsNetworkAccess
        let accumulator = HashAccumulator()

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: original,
                options: options,
                dataReceivedHandler: { data in
                    accumulator.update(with: data)
                },
                completionHandler: { error in
                    continuation.resume(returning: error == nil ? accumulator.finalize() : nil)
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
