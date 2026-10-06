#if canImport(Photos)
import CoreGraphics
import Foundation
import Photos

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Die echte Mediathek über PhotoKit, auf iPhone, iPad und Mac gleich.
///
/// Lädt nur lokal vorhandene Vorschaubilder, nie Originale aus iCloud
/// (siehe `ScanPolicy`). Auf dem Mac sieht PhotoKit nur die Systemmediathek.
public struct PhotoKitSource: PhotoSource, LibraryChangeTracker {
    public init() {}

    // MARK: Berechtigung

    public func access() -> LibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> LibraryAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    static func map(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .authorized: return .full
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default:
            #if os(iOS)
            if status == .limited { return .limited }
            #endif
            return .denied
        }
    }

    // MARK: Einträge

    public func fetchRecords() async throws -> [AssetRecord] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Nur die eigene Mediathek. Geteilte Alben und per Kabel synchronisierte
        // Fotos lassen sich ohnehin nicht löschen.
        options.includeAssetSourceTypes = [.typeUserLibrary]

        let result = PHAsset.fetchAssets(with: options)
        var records: [AssetRecord] = []
        records.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            records.append(Self.record(from: asset))
        }
        return records
    }

    static func record(from asset: PHAsset) -> AssetRecord {
        var traits: AssetTraits = []
        if asset.mediaSubtypes.contains(.photoScreenshot) { traits.insert(.screenshot) }
        if asset.mediaSubtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if asset.representsBurst || asset.burstIdentifier != nil { traits.insert(.burst) }

        return AssetRecord(
            id: AssetID(asset.localIdentifier),
            kind: kind(of: asset.mediaType),
            traits: traits,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            hasAdjustments: asset.hasAdjustments,
            burstIdentifier: asset.burstIdentifier
        )
    }

    static func kind(of mediaType: PHAssetMediaType) -> AssetKind {
        switch mediaType {
        case .image: .photo
        case .video: .video
        default: .other
        }
    }

    // MARK: Vorschaubilder

    public func thumbnail(for id: AssetID, maxPixelSize: Int) async -> Thumbnail? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id.rawValue], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = Self.makeThumbnailOptions()
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)

        return await withCheckedContinuation { continuation in
            // Mit .highQualityFormat ruft PhotoKit den Block genau einmal auf.
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                let cgImage = image.flatMap(Self.cgImage(from:))
                continuation.resume(returning: cgImage.map(Thumbnail.init(cgImage:)))
            }
        }
    }

    /// Anfrageoptionen für Vorschaubilder. Der Test prüft, dass kein Netz erlaubt ist.
    static func makeThumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = ScanPolicy.allowsNetworkAccess
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.version = .current
        options.isSynchronous = false
        return options
    }

    #if canImport(UIKit)
    static func cgImage(from image: UIImage) -> CGImage? {
        image.cgImage
    }
    #elseif canImport(AppKit)
    static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    #endif

    // MARK: Änderungen seit dem letzten Scan

    public func currentChangeToken() async throws -> ChangeToken {
        let token = PHPhotoLibrary.shared().currentChangeToken
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        return ChangeToken(data: data)
    }

    public func changes(since token: ChangeToken) async throws -> LibraryChangeResult {
        guard
            let previous = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: PHPersistentChangeToken.self,
                from: token.data
            )
        else { return .fullScanRequired }

        let persistentChanges: PHPersistentChangeFetchResult
        do {
            persistentChanges = try PHPhotoLibrary.shared().fetchPersistentChanges(since: previous)
        } catch {
            // Abgelaufener Merkzettel oder fehlende Details: einmal alles neu lesen.
            return .fullScanRequired
        }

        var changes = LibraryChanges()
        for change in persistentChanges {
            guard let details = try? change.changeDetails(for: PHObjectType.asset) else {
                return .fullScanRequired
            }
            changes.merge(LibraryChanges(
                inserted: Set(details.insertedLocalIdentifiers.map(AssetID.init)),
                updated: Set(details.updatedLocalIdentifiers.map(AssetID.init)),
                deleted: Set(details.deletedLocalIdentifiers.map(AssetID.init))
            ))
        }
        return .changes(changes)
    }
}
#endif
