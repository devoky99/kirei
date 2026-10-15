import KireiCore
import KireiUI
import SwiftUI

/// Alle Fotos, wie Fotos sie zeigt. Aus Phase 0, zur Kontrolle.
struct LibraryGridView: View {
    @Environment(LibraryModel.self) private var library

    private let columns = [
        GridItem(.adaptive(minimum: PlatformMetrics.tileMinimum), spacing: KireiTheme.Spacing.tile),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: KireiTheme.Spacing.tile) {
                ForEach(library.records) { record in
                    ThumbnailCell(record: record)
                }
            }
            .padding(KireiTheme.Spacing.medium)
        }
        .overlay {
            if library.records.isEmpty && library.isScanning {
                ProgressView("Reading your library…")
            }
        }
        .navigationTitle(Text("All photos"))
    }
}

private struct ThumbnailCell: View {
    @Environment(LibraryModel.self) private var library
    let record: AssetRecord
    @State private var thumbnail: Thumbnail?

    var body: some View {
        PhotoTile(thumbnail: thumbnail, badgeSystemImage: badge)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .task(id: record.id) {
                thumbnail = await library.thumbnail(for: record.id)
            }
    }

    private var badge: String? {
        if record.kind == .video { return "video.fill" }
        if record.isScreenshot { return "camera.viewfinder" }
        return nil
    }

    private var accessibilityLabel: Text {
        let date = record.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        switch record.kind {
        case .video:
            return Text("Video, \(date)")
        case .photo where record.isScreenshot:
            return Text("Screenshot, \(date)")
        case .photo, .other:
            return Text("Photo, \(date)")
        }
    }
}
