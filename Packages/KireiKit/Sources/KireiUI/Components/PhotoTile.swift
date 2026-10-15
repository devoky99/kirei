import ImageIO
import KireiCore
import SwiftUI

/// Quadratische Fotokachel für Raster und Gruppen auf allen Geräten.
///
/// Die Kachel selbst ist für VoiceOver unsichtbar. Die Beschriftung setzt
/// die Ansicht, die weiß, was das Foto ist.
public struct PhotoTile: View {
    private let thumbnail: Thumbnail?
    private let badgeSystemImage: String?

    public init(thumbnail: Thumbnail?, badgeSystemImage: String? = nil) {
        self.thumbnail = thumbnail
        self.badgeSystemImage = badgeSystemImage
    }

    public var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail.cgImage, scale: 1, orientation: Self.orientation(thumbnail.orientation))
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KireiTheme.Radius.tile, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let badgeSystemImage {
                    Image(systemName: badgeSystemImage)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(KireiTheme.Spacing.small)
                }
            }
            .animation(KireiTheme.Motion.gentle, value: thumbnail != nil)
    }

    static func orientation(_ orientation: CGImagePropertyOrientation) -> Image.Orientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
