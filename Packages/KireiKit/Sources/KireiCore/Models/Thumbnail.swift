import CoreGraphics

/// Ein Vorschaubild als plattformneutrales `CGImage`.
///
/// UIImage gibt es nur auf iOS, NSImage nur auf dem Mac. Der Kern arbeitet
/// deshalb immer mit `CGImage`, die Fotoquelle übersetzt.
public struct Thumbnail: @unchecked Sendable {
    // CGImage ist unveränderlich und darf zwischen Threads wandern.
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public var pixelWidth: Int { cgImage.width }
    public var pixelHeight: Int { cgImage.height }
}
