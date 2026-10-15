import CoreGraphics
import ImageIO

/// Ein Vorschaubild als plattformneutrales `CGImage`.
///
/// UIImage gibt es nur auf iOS, NSImage nur auf dem Mac. Der Kern arbeitet
/// deshalb immer mit `CGImage`, die Fotoquelle übersetzt.
public struct Thumbnail: @unchecked Sendable {
    // CGImage ist unveränderlich und darf zwischen Threads wandern.
    public let cgImage: CGImage
    /// Wie das Bild gedreht werden muss, damit es aufrecht steht.
    public let orientation: CGImagePropertyOrientation

    public init(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.cgImage = cgImage
        self.orientation = orientation
    }

    public var pixelWidth: Int { cgImage.width }
    public var pixelHeight: Int { cgImage.height }

    /// Breite und Höhe nach dem Aufrichten.
    public var orientedSize: CGSize {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}

/// Wie ein Vorschaubild zugeschnitten wird.
public enum ThumbnailMode: Sendable {
    /// Füllt ein Quadrat, für Kacheln im Raster.
    case fill
    /// Ganzes Bild, längste Seite höchstens so groß wie verlangt. Für die Analyse.
    case fit
}
