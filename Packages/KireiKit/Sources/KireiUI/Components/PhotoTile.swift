import CoreGraphics
import SwiftUI

/// Quadratische Fotokachel für das Raster auf allen Geräten.
///
/// Die Kachel selbst ist für VoiceOver unsichtbar. Die Beschriftung setzt
/// die Ansicht, die weiß, was das Foto ist.
public struct PhotoTile: View {
    private let image: CGImage?
    private let badgeSystemImage: String?

    public init(image: CGImage?, badgeSystemImage: String? = nil) {
        self.image = image
        self.badgeSystemImage = badgeSystemImage
    }

    public var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
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
            .animation(KireiTheme.Motion.gentle, value: image != nil)
    }
}
