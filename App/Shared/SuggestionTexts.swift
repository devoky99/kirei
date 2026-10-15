import Foundation
import KireiCore

// Texte zu den Kategorien und Begründungen aus dem Kern.
// Der Kern kennt keine Sprache, die Übersetzungen liegen im String Catalog.

extension SuggestionCategory {
    var title: LocalizedStringResource {
        switch self {
        case .exactDuplicates: "Exact duplicates"
        case .similar: "Similar photos"
        case .bursts: "Bursts"
        case .blurry: "Blurry photos"
        case .screenshots: "Screenshots"
        case .screenRecordings: "Screen recordings"
        case .largeVideos: "Large videos"
        }
    }

    var systemImage: String {
        switch self {
        case .exactDuplicates: "plus.square.on.square"
        case .similar: "square.stack"
        case .bursts: "square.stack.3d.down.right"
        case .blurry: "camera.metering.unknown"
        case .screenshots: "camera.viewfinder"
        case .screenRecordings: "record.circle"
        case .largeVideos: "video"
        }
    }
}

extension SuggestionReason {
    var text: LocalizedStringResource {
        switch self {
        case .bestOfGroup:
            "Best photo in this group"
        case .sharpest:
            "Sharpest"
        case .eyesOpen:
            "Eyes open"
        case .original:
            "Kept as the original"
        case .burstSelection:
            "Selected in the burst"
        case .protected(.favorite):
            "Favorite, never suggested"
        case .protected(.edited):
            "Edited, never suggested"
        case .protected(.inAlbum):
            "In one of your albums, never suggested"
        case .exactCopy:
            "Exact copy"
        case .probableCopy:
            "Probably a copy (original in iCloud)"
        case .nearlyIdentical:
            "Almost the same as the photo you keep"
        case .lessSharp:
            "Less sharp than the photo you keep"
        case .eyesClosed:
            "Eyes closed"
        case .unselectedBurstFrame:
            "Not selected in the burst"
        case .blurry:
            "Looks blurry"
        case .screenshot(let days):
            "Screenshot from \(days) days ago"
        case .screenRecording(let seconds):
            "Screen recording, \(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))"
        case .largeVideo(let bytes):
            "About \(bytes.formatted(.byteCount(style: .file)))"
        }
    }
}
