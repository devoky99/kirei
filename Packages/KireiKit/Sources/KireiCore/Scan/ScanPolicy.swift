/// Regeln, die für jeden Scan gelten. Sie sind nicht verhandelbar
/// (siehe CLAUDE.md) und werden hier an genau einer Stelle festgelegt.
public enum ScanPolicy {
    /// Der Scan nutzt nie das Netz und lädt nichts aus iCloud.
    /// Liegt nur eine iCloud-Version vor, wird das Foto übersprungen.
    /// Gilt für Vorschaubilder und für Prüfsummen lokaler Originale.
    public static let allowsNetworkAccess = false

    /// Kantenlänge der Vorschaubilder im Raster, in Pixeln.
    public static let gridThumbnailPixelSize = 300

    /// Längste Seite der Vorschaubilder für die Analyse, in Pixeln.
    /// Vision rechnet intern ohnehin mit kleineren Bildern.
    public static let analysisThumbnailPixelSize = 512
}
