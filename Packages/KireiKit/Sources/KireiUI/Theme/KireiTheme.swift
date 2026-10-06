import SwiftUI

/// Gestaltungswerte für iPhone, iPad und Mac: viel Weißraum, ein Akzent, ruhige Bewegung.
///
/// Platzhalter, bis die Werte aus Mirai übernommen sind. Die Akzentfarbe
/// selbst liegt im Asset-Katalog der App (`AccentColor`).
public enum KireiTheme {
    public enum Spacing {
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xLarge: CGFloat = 40
        /// Abstand zwischen Kacheln im Raster.
        public static let tile: CGFloat = 2
    }

    public enum Radius {
        public static let tile: CGFloat = 6
        public static let card: CGFloat = 14
    }

    public enum Motion {
        /// Sanft und kurz. Bei „Bewegung reduzieren“ entfällt die Animation.
        public static var gentle: Animation { .easeInOut(duration: 0.25) }
    }

    public enum Layout {
        /// Höchstbreite für Erklärtexte, damit Zeilen auf dem Mac nicht ausufern.
        public static let readableWidth: CGFloat = 480
    }
}
