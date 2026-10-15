import KireiCore
import KireiUI
import SwiftUI

/// Testoberfläche aus Phase 1: Fortschritt und Vorschläge je Kategorie.
/// Phase 2 ersetzt das durch Bilanz, Seitenleiste und Prüfkorb.
struct ScanOverviewView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        List {
            Section {
                SummaryRow(summary: library.results.summary, newCount: library.newSinceLastScan)
                if let progress = library.progress {
                    ScanProgressRow(progress: progress)
                }
                if library.results.counts.unavailable > 0 {
                    Text("\(library.results.counts.unavailable) photos were skipped, usually because they are only in iCloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if library.access == .limited {
                    LimitedAccessNote()
                }
                if library.failed {
                    Text("The library could not be read. Please try again.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(SuggestionCategory.allCases, id: \.self) { category in
                    let groups = library.results.groups(in: category)
                    if !groups.isEmpty {
                        NavigationLink(value: category) {
                            CategoryRow(category: category, groups: groups)
                        }
                    }
                }
                if library.hasScanned && library.results.groups.isEmpty {
                    Text("Nothing to tidy up right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Suggestions")
            }

            Section {
                NavigationLink {
                    LibraryGridView()
                } label: {
                    Label {
                        Text("All photos")
                    } icon: {
                        Image(systemName: "square.grid.3x3")
                    }
                }
                #if DEBUG
                NavigationLink {
                    ReviewView()
                } label: {
                    Label {
                        Text(verbatim: "Prüfmodus (nur Entwicklung)")
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                }
                #endif
            }
        }
        .navigationDestination(for: SuggestionCategory.self) { category in
            SuggestionListView(category: category)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActionButton(AppActions.refresh) {
                    library.startScan()
                }
                .disabled(library.isScanning)
            }
        }
        .task {
            if !library.hasScanned {
                library.startScan()
            }
        }
    }
}

private struct ScanProgressRow: View {
    let progress: ScanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.small) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction) { label }
            } else {
                ProgressView { label }
            }
        }
        .padding(.vertical, KireiTheme.Spacing.xSmall)
    }

    @ViewBuilder
    private var label: some View {
        switch progress.stage {
        case .reading:
            Text("Reading your library…")
        case .analyzing:
            Text("Looking at photos: \(progress.completed) of \(progress.total)")
        case .comparing:
            Text("Comparing similar photos…")
        case .faces:
            Text("Checking faces: \(progress.completed) of \(progress.total)")
        case .paused:
            Text("Paused while your device cools down.")
        case .finished:
            EmptyView()
        }
    }
}

private struct CategoryRow: View {
    let category: SuggestionCategory
    let groups: [SuggestionGroup]

    private var suggestionCount: Int {
        groups.reduce(0) { $0 + $1.suggested.count }
    }

    private var savings: Int64 {
        groups.reduce(0) { $0 + $1.estimatedSavings }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) {
                Text(category.title)
                Text("\(suggestionCount) suggestions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if savings > 0 {
                    Text("about \(savings.formatted(.byteCount(style: .file)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: category.systemImage)
        }
    }
}

struct SummaryRow: View {
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

struct LimitedAccessNote: View {
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
