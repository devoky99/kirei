#if os(macOS)
import Foundation

/// Werte, die sich auf dem Mac von iPhone und iPad unterscheiden.
enum PlatformMetrics {
    /// Kleinste Kachelbreite im Raster, in Punkten.
    static let tileMinimum: CGFloat = 132
}

enum PlatformSettings {
    /// Öffnet Systemeinstellungen > Datenschutz & Sicherheit > Fotos.
    @MainActor
    static var photoPrivacySettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
    }
}
#endif
