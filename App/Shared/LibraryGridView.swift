import KireiCore
import KireiUI
import SwiftUI

/// Durchstich aus Phase 0: alle lokalen Vorschaubilder in einem Raster.
struct LibraryGridView: View {
    @Environment(LibraryModel.self) private var library

    private let columns = [
        GridItem(.adaptive(minimum: PlatformMetrics.tileMinimum), spacing: KireiTheme.Spacing.tile),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.medium) {
                if library.access == .limited {
                    LimitedAccessNote()
                }

                SummaryRow(summary: library.summary, newCount: library.newSinceLastScan)

                LazyVGrid(columns: columns, spacing: KireiTheme.Spacing.tile) {
                    ForEach(library.records) { record in
                        ThumbnailCell(record: record)
                    }
                }
            }
            .padding(KireiTheme.Spacing.medium)
        }
        .overlay {
            if library.phase == .loading, library.records.isEmpty {
                ProgressView("Reading your library…")
            } else if library.phase == .failed {
                Text("The library could not be read. Please try again.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActionButton(AppActions.refresh) {
                    Task { await library.refresh() }
                }
            }
        }
        .task {
            if library.phase == .idle {
                await library.refresh()
            }
        }
    }
}

private struct SummaryRow: View {
    let summary: LibrarySummary
    let newCount: Int?

    var body: some View {
        // Bei großer Schrift untereinander statt nebeneinander.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KireiTheme.Spacing.medium) { items }
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) { items }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var items: some View {
        Text("\(summary.photos) photos")
        Text("\(summary.videos) videos")
        Text("\(summary.screenshots) screenshots")
        if let newCount, newCount > 0 {
            Text("\(newCount) new since last time")
                .foregroundStyle(.tint)
        }
    }
}

private struct LimitedAccessNote: View {
    var body: some View {
        Label {
            Text("Limited access: Kirei only sees the photos you selected.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct ThumbnailCell: View {
    @Environment(LibraryModel.self) private var library
    let record: AssetRecord
    @State private var thumbnail: Thumbnail?

    var body: some View {
        PhotoTile(image: thumbnail?.cgImage, badgeSystemImage: badge)
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
