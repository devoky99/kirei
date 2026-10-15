#if canImport(Photos)
import CoreGraphics
import Foundation
import ImageIO
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
        let albumMembers = Self.assetIDs(in: PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        ))
        // Bildschirmaufnahmen kennt PhotoKit nur als intelligentes Album (ab iOS 18, macOS 15).
        let screenRecordings = Self.assetIDs(in: PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenRecordings, options: nil
        ))

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Nur die eigene Mediathek. Geteilte Alben und per Kabel synchronisierte
        // Fotos lassen sich ohnehin nicht löschen.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        // Auch die verborgenen Bilder von Serien, sie belegen Platz.
        options.includeAllBurstAssets = true

        let result = PHAsset.fetchAssets(with: options)
        var records: [AssetRecord] = []
        records.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            records.append(Self.record(
                from: asset,
                inUserAlbum: albumMembers.contains(asset.localIdentifier),
                isScreenRecording: screenRecordings.contains(asset.localIdentifier)
            ))
        }
        return records
    }

    /// Alle Einträge in diesen Alben, etwa für die Schutzregel „in einem eigenen Album“.
    static func assetIDs(in albums: PHFetchResult<PHAssetCollection>) -> Set<String> {
        var ids = Set<String>()
        albums.enumerateObjects { album, _, _ in
            let assets = PHAsset.fetchAssets(in: album, options: nil)
            assets.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }

    static func record(from asset: PHAsset, inUserAlbum: Bool, isScreenRecording: Bool) -> AssetRecord {
        var traits: AssetTraits = []
        let subtypes = asset.mediaSubtypes
        if subtypes.contains(.photoScreenshot) { traits.insert(.screenshot) }
        if subtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if isScreenRecording { traits.insert(.screenRecording) }
        if asset.burstIdentifier != nil { traits.insert(.burst) }
        if asset.representsBurst { traits.insert(.burstRepresentative) }
        let selection = asset.burstSelectionTypes
        if selection.contains(.userPick) { traits.insert(.burstUserPick) }
        if selection.contains(.autoPick) { traits.insert(.burstAutoPick) }

        return AssetRecord(
            id: AssetID(asset.localIdentifier),
            kind: kind(of: asset.mediaType),
            traits: traits,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            hasAdjustments: asset.hasAdjustments,
            isInUserAlbum: inUserAlbum,
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

    public func thumbnail(for id: AssetID, maxPixelSize: Int, mode: ThumbnailMode) async -> Thumbnail? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id.rawValue], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = Self.makeThumbnailOptions()
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)
        let contentMode: PHImageContentMode = mode == .fill ? .aspectFill : .aspectFit

        return await withCheckedContinuation { continuation in
            // Mit .highQualityFormat ruft PhotoKit den Block genau einmal auf.
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image.flatMap(Self.thumbnail(from:)))
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
    static func thumbnail(from image: UIImage) -> Thumbnail? {
        guard let cgImage = image.cgImage else { return nil }
        return Thumbnail(cgImage: cgImage, orientation: orientation(of: image.imageOrientation))
    }

    static func orientation(of orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
    #elseif canImport(AppKit)
    static func thumbnail(from image: NSImage) -> Thumbnail? {
        // Auf dem Mac liefert PhotoKit das Bild bereits aufrecht.
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return Thumbnail(cgImage: cgImage)
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
