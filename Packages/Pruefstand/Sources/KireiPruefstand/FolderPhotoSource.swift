import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import KireiCore

/// Fotoquelle aus einem Ordner mit Testbildern, auch in Unterordnern.
///
/// Die Kennung ist der Pfad relativ zum Ordner. Das Datum stammt aus den
/// EXIF-Daten, ohne EXIF aus dem Änderungsdatum der Datei. So rechnet der
/// Kern genau wie in der App, nur ohne PhotoKit.
struct FolderPhotoSource: PhotoSource {
    let folder: URL

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]

    init(folder: URL) {
        self.folder = folder.standardizedFileURL
    }

    func access() -> LibraryAccess { .full }

    func requestAccess() async -> LibraryAccess { .full }

    func fetchRecords() async throws -> [AssetRecord] {
        imageFiles()
            .compactMap(record(for:))
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func thumbnail(for id: AssetID, maxPixelSize: Int, mode: ThumbnailMode) async -> Thumbnail? {
        let url = self.url(for: id)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Mit Transform liefert ImageIO das Bild bereits aufrecht.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Thumbnail(cgImage: image)
    }

    func url(for id: AssetID) -> URL {
        folder.appending(path: id.rawValue)
    }

    /// Synchron, weil der Verzeichnis-Durchlauf in async-Kontexten nicht erlaubt ist.
    func imageFiles(in directory: URL? = nil) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory ?? folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            files.append(url.standardizedFileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    func relativePath(of url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(folder.path.count + 1))
    }

    private func record(for url: URL) -> AssetRecord? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let exifDate = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.parseExifDate)
        let fileDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        return AssetRecord(
            id: AssetID(relativePath(of: url)),
            kind: .photo,
            creationDate: exifDate ?? fileDate,
            modificationDate: fileDate,
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    /// EXIF-Datum im Format „2026:10:06 14:30:00“, ohne Zeitzone.
    static func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

/// Prüfsumme der Datei, wie in der App die des lokalen Originals.
struct FileContentHasher: ContentHasher {
    let source: FolderPhotoSource

    func contentHash(for id: AssetID) async -> Data? {
        guard let data = try? Data(contentsOf: source.url(for: id)) else { return nil }
        return Data(SHA256.hash(data: data))
    }
}
