#if os(iOS)
import UIKit

/// Werte, die sich auf iPhone und iPad vom Mac unterscheiden.
enum PlatformMetrics {
    /// Kleinste Kachelbreite im Raster, in Punkten.
    static let tileMinimum: CGFloat = 96
}

enum PlatformSettings {
    /// Öffnet die Einstellungen der App, dort liegt der Fotozugriff.
    @MainActor
    static var photoPrivacySettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
#endif
