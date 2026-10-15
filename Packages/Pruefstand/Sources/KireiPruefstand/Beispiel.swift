import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Legt erzeugte Beispielbilder an, um den Prüfstand auszuprobieren.
///
/// Keine echten Fotos, nur Formen in Farben. Reicht, um alle Befehle einmal
/// durchlaufen zu lassen. Für Prüfpunkt 1 zählt nur die eigene Mediathek.
enum Beispiel {
    struct Motiv {
        let hue: CGFloat
        let shape: Int
    }

    static func run(folder: URL) -> Int32 {
        let library = folder.appending(path: "mediathek")
        let calibration = folder.appending(path: "kalibrierung")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var written = 0

        do {
            // Drei Serien mit je vier fast gleichen Aufnahmen, fünf Sekunden auseinander.
            for series in 0..<3 {
                let motif = Motiv(hue: CGFloat(series) / 3, shape: series)
                for shot in 0..<4 {
                    let date = start.addingTimeInterval(Double(series) * 3_600 + Double(shot) * 5)
                    let image = draw(motif, offset: CGFloat(shot) * 4, blur: shot == 3)
                    try write(image, to: library.appending(path: "serie\(series + 1)-\(shot + 1).jpg"), date: date)
                    try write(image, to: calibration.appending(path: "aehnlich/serie\(series + 1)/\(shot + 1).jpg"), date: date)
                    written += 1
                }
            }

            // Einzelne Motive, jeweils weit auseinander.
            for single in 0..<6 {
                let motif = Motiv(hue: CGFloat(single) / 6 + 0.08, shape: single + 3)
                let date = start.addingTimeInterval(20_000 + Double(single) * 3_600)
                try write(draw(motif, offset: 0, blur: false), to: library.appending(path: "einzeln\(single + 1).jpg"), date: date)
                written += 1
            }

            // Eine exakte Kopie: gleiche Datei unter anderem Namen.
            let original = library.appending(path: "einzeln1.jpg")
            try FileManager.default.copyItem(at: original, to: library.appending(path: "einzeln1-kopie.jpg"))
            written += 1

            // Verschiedene Motive mit ähnlichen Farben, zum Kalibrieren.
            for pair in 0..<3 {
                for variant in 0..<2 {
                    let motif = Motiv(hue: CGFloat(pair) / 3, shape: pair * 2 + variant + 10)
                    try write(draw(motif, offset: 0, blur: false), to: calibration.appending(path: "verschieden/paar\(pair + 1)/\(variant + 1).jpg"), date: start)
                }
            }

            // Scharf und unscharf.
            for index in 0..<4 {
                let motif = Motiv(hue: CGFloat(index) / 4, shape: index + 20)
                try write(draw(motif, offset: 0, blur: false), to: calibration.appending(path: "scharf/\(index + 1).jpg"), date: start)
                try write(draw(motif, offset: 0, blur: true), to: calibration.appending(path: "unscharf/\(index + 1).jpg"), date: start)
            }
        } catch {
            print("Beispielbilder ließen sich nicht schreiben: \(error.localizedDescription)")
            return 1
        }

        print("\(written) Beispielfotos in \(library.path)")
        print("Kalibrierbeispiele in \(calibration.path)")
        print("Gesichter lassen sich nicht erzeugen, augen_zu und augen_offen bleiben leer.")
        return 0
    }

    // MARK: Zeichnen

    static func draw(_ motif: Motiv, offset: CGFloat, blur: Bool) -> CGImage {
        let size = 800
        // Unscharf: klein zeichnen und groß skalieren.
        let scale: CGFloat = blur ? 0.06 : 1
        let small = render(motif, offset: offset, width: Int(CGFloat(size) * scale), height: Int(CGFloat(size) * 0.75 * scale), unit: scale)
        guard blur else { return small }
        return resize(small, width: size, height: Int(CGFloat(size) * 0.75))
    }

    static func render(_ motif: Motiv, offset: CGFloat, width: Int, height: Int, unit: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: max(width, 2),
            height: max(height, 2),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: unit, y: unit)
        context.setFillColor(color(hue: motif.hue, saturation: 0.15, brightness: 0.95))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))

        var generator = motif.shape &* 7_919 &+ 17
        func next() -> CGFloat {
            generator = (generator &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
            return CGFloat(generator % 1_000) / 1_000
        }

        for index in 0..<12 {
            let hue = (motif.hue + next() * 0.3).truncatingRemainder(dividingBy: 1)
            context.setFillColor(color(hue: hue, saturation: 0.7, brightness: 0.4 + next() * 0.5))
            let rect = CGRect(x: 40 + next() * 620 + offset, y: 40 + next() * 420, width: 40 + next() * 160, height: 40 + next() * 160)
            if index % 2 == 0 {
                context.fillEllipse(in: rect)
            } else {
                context.fill(rect)
            }
        }
        return context.makeImage()!
    }

    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> CGColor {
        // HSB nach RGB, ohne AppKit.
        let h = (hue.truncatingRemainder(dividingBy: 1)) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: (CGFloat, CGFloat, CGFloat) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return CGColor(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m, alpha: 1)
    }

    // MARK: Schreiben

    static func write(_ image: CGImage, to url: URL, date: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date),
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
