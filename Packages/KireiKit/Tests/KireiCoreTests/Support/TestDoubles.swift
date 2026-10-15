import CoreGraphics
import Foundation
@testable import KireiCore

/// Erzeugt einfache Testbilder ohne Dateien.
enum TestImages {
    /// Graustufenbild, dessen Pixel eine Funktion liefert.
    static func gray(width: Int, height: Int, pixel: (Int, Int) -> UInt8) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = pixel(x, y)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Schachbrett mit harten Kanten: sehr scharf.
    static func checkerboard(size: Int = 128, cell: Int = 8) -> CGImage {
        gray(width: size, height: size) { x, y in ((x / cell) + (y / cell)) % 2 == 0 ? 255 : 0 }
    }

    /// Weicher Verlauf ohne Kanten: wirkt unscharf.
    static func gradient(size: Int = 128) -> CGImage {
        gray(width: size, height: size) { x, _ in UInt8(x * 255 / max(size - 1, 1)) }
    }

    /// Einfarbig, Breite als Erkennungszeichen für `FakeAnalyzer`.
    static func marker(width: Int) -> CGImage {
        gray(width: width, height: 16) { _, _ in 128 }
    }
}

/// Nachgebaute Mediathek. Jedes Foto bekommt ein Vorschaubild, dessen Breite
/// die Nummer des Fotos verrät. Fotos in `cloudOnly` haben kein lokales Bild.
struct FakePhotoSource: PhotoSource {
    let records: [AssetRecord]
    var cloudOnly: Set<AssetID> = []

    func access() -> LibraryAccess { .full }

    func requestAccess() async -> LibraryAccess { .full }

    func fetchRecords() async throws -> [AssetRecord] { records }

    func thumbnail(for id: AssetID, maxPixelSize: Int, mode: ThumbnailMode) async -> Thumbnail? {
        guard !cloudOnly.contains(id), let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        return Thumbnail(cgImage: TestImages.marker(width: FakeAnalyzer.width(forIndex: index)))
    }
}

/// Liefert vorgegebene Analysen statt Vision. Erkennt das Foto an der Bildbreite.
struct FakeAnalyzer: ImageAnalyzer {
    let version = 1
    let records: [AssetRecord]
    let analyses: [AssetID: ImageAnalysis]
    var faces: [AssetID: FaceSummary] = [:]

    static func width(forIndex index: Int) -> Int { 10 + index }

    private func id(for thumbnail: Thumbnail) -> AssetID? {
        let index = thumbnail.pixelWidth - 10
        guard records.indices.contains(index) else { return nil }
        return records[index].id
    }

    func analyze(_ thumbnail: Thumbnail) async throws -> ImageAnalysis {
        guard let id = id(for: thumbnail), let analysis = analyses[id] else {
            return ImageAnalysis(featurePrint: nil, aestheticScore: nil, isUtility: false, sharpness: 0)
        }
        return analysis
    }

    func analyzeFaces(_ thumbnail: Thumbnail) async throws -> FaceSummary {
        guard let id = id(for: thumbnail) else { return .none }
        return faces[id] ?? .none
    }
}

struct FakeHasher: ContentHasher {
    let hashes: [AssetID: Data]

    func contentHash(for id: AssetID) async -> Data? { hashes[id] }
}

/// Merkmalsvektor in Richtung einer Achse, leicht verschoben. Gleiche Achse
/// und kleine Verschiebung heißt fast gleich.
func testPrint(axis: Int, nudge: Float = 0, dimensions: Int = 8) -> FeaturePrint {
    var vector = [Float](repeating: 0, count: dimensions)
    vector[axis % dimensions] = 1
    vector[(axis + 1) % dimensions] = nudge
    return FeaturePrint(vector: vector)
}

func photo(
    _ id: String,
    at seconds: TimeInterval,
    favorite: Bool = false,
    width: Int = 4032,
    height: Int = 3024
) -> AssetRecord {
    AssetRecord(
        id: AssetID(id),
        kind: .photo,
        creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds),
        modificationDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
        pixelWidth: width,
        pixelHeight: height,
        isFavorite: favorite
    )
}

func analyzed(
    _ id: String,
    at seconds: TimeInterval,
    print: FeaturePrint?,
    aesthetic: Float? = 0.2,
    sharpness: Double = 100,
    utility: Bool = false
) -> AnalyzedPhoto {
    AnalyzedPhoto(
        id: AssetID(id),
        date: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds),
        featurePrint: print,
        aestheticScore: aesthetic,
        isUtility: utility,
        sharpness: sharpness
    )
}
