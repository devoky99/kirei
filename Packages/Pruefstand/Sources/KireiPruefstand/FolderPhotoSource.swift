import CoreGraphics
import Foundation
import ImageIO
import KireiCore

/// Fotoquelle aus einem Ordner mit Testbildern.
///
/// Die Kennung ist der Pfad relativ zum Ordner, das Datum stammt aus den
/// EXIF-Daten. So rechnet der Kern genau wie in der App, nur ohne PhotoKit.
struct FolderPhotoSource: PhotoSource {
    let folder: URL

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]

    func access() -> LibraryAccess { .full }

    func requestAccess() async -> LibraryAccess { .full }

    func fetchRecords() async throws -> [AssetRecord] {
        imageFiles()
            .compactMap(record(for:))
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func thumbnail(for id: AssetID, maxPixelSize: Int) async -> Thumbnail? {
        let url = folder.appending(path: id.rawValue)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Thumbnail(cgImage: image)
    }

    /// Synchron, weil der Verzeichnis-Durchlauf in async-Kontexten nicht erlaubt ist.
    private func imageFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            files.append(url)
        }
        return files
    }

    private func record(for url: URL) -> AssetRecord? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        let relativePath = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))

        return AssetRecord(
            id: AssetID(relativePath),
            kind: .photo,
            creationDate: dateString.flatMap(Self.parseExifDate),
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
