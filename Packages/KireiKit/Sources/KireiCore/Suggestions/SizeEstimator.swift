import Foundation

/// Schätzt die Dateigröße aus Auflösung und Dauer.
///
/// Die genaue Größe liefert PhotoKit nur über eine nicht dokumentierte
/// Eigenschaft. Entscheidung aus der Roadmap: schätzen und in der App
/// immer „etwa“ dazuschreiben.
public enum SizeEstimator {
    /// Pixel eines 1080p-Videos.
    static let fullHDPixels = 1920.0 * 1080.0

    public static func estimatedBytes(for record: AssetRecord) -> Int64 {
        let pixels = Double(max(record.pixelWidth, 1)) * Double(max(record.pixelHeight, 1))
        switch record.kind {
        case .video:
            // Näherung an die Kamera-Einstellungen des iPhone (HEVC, 30 Bilder
            // pro Sekunde): 1080p etwa 60 MB, 4K etwa 170 MB pro Minute.
            let megabytesPerMinute = 60 * pow(pixels / fullHDPixels, 0.75)
            return Int64(megabytesPerMinute * 1_000_000 * max(record.duration, 0) / 60)
        case .photo:
            // HEIC-Fotos etwa 0,2 Byte pro Pixel, PNG-Bildschirmfotos deutlich mehr.
            let bytesPerPixel = record.isScreenshot ? 0.6 : 0.2
            var bytes = pixels * bytesPerPixel
            if record.traits.contains(.livePhoto) {
                bytes += 2_500_000
            }
            return Int64(bytes)
        case .other:
            return 0
        }
    }
}
