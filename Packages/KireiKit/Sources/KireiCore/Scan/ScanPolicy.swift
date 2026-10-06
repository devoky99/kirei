/// Regeln, die für jeden Scan gelten. Sie sind nicht verhandelbar
/// (siehe CLAUDE.md) und werden hier an genau einer Stelle festgelegt.
public enum ScanPolicy {
    /// Der Scan nutzt nie das Netz und lädt keine Originale aus iCloud.
    /// Liegt nur eine iCloud-Version vor, wird das Foto übersprungen.
    public static let allowsNetworkAccess = false

    /// Kantenlänge der Vorschaubilder im Raster, in Pixeln.
    public static let gridThumbnailPixelSize = 300
}
