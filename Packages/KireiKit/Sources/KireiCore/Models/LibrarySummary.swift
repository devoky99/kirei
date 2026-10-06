/// Zählt, was in der Mediathek liegt. Grundlage für die spätere Speicher-Bilanz.
public struct LibrarySummary: Sendable, Equatable {
    /// Fotos ohne Bildschirmfotos.
    public let photos: Int
    public let videos: Int
    public let screenshots: Int

    public init(photos: Int, videos: Int, screenshots: Int) {
        self.photos = photos
        self.videos = videos
        self.screenshots = screenshots
    }

    public init(records: some Sequence<AssetRecord>) {
        var photos = 0
        var videos = 0
        var screenshots = 0
        for record in records {
            switch record.kind {
            case .photo where record.isScreenshot:
                screenshots += 1
            case .photo:
                photos += 1
            case .video:
                videos += 1
            case .other:
                break
            }
        }
        self.init(photos: photos, videos: videos, screenshots: screenshots)
    }

    public static let empty = LibrarySummary(photos: 0, videos: 0, screenshots: 0)
}
