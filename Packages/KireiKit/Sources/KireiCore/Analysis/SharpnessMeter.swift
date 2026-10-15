import CoreGraphics

/// Eigene Schärfemessung als Zweitmeinung zum Ästhetik-Score von Vision.
///
/// Misst, wie stark sich benachbarte Pixel unterscheiden (Varianz des
/// Laplace-Filters auf einem Graustufenbild). Scharfe Kanten ergeben hohe
/// Werte, Unschärfe und Verwacklung niedrige. Der Wert hängt vom Motiv ab,
/// deshalb entscheidet er nie allein.
public enum SharpnessMeter {
    /// Höher heißt schärfer. Das Bild wird vorher auf `maxSide` verkleinert,
    /// damit Werte verschiedener Fotos vergleichbar sind.
    public static func measure(_ image: CGImage, maxSide: Int = 512) -> Double {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return 0 }
        let factor = min(1, Double(maxSide) / Double(longest))
        let width = max(3, Int((Double(image.width) * factor).rounded()))
        let height = max(3, Int((Double(image.height) * factor).rounded()))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        return laplacianVariance(pixels, width: width, height: height)
    }

    static func laplacianVariance(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width >= 3, height >= 3, pixels.count >= width * height else { return 0 }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let index = row + x
                let neighbours = Int(pixels[index - 1]) + Int(pixels[index + 1])
                    + Int(pixels[index - width]) + Int(pixels[index + width])
                let value = Double(neighbours - 4 * Int(pixels[index]))
                sum += value
                sumOfSquares += value * value
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, sumOfSquares / count - mean * mean)
    }
}
