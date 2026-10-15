import KireiCore
import KireiUI
import SwiftUI

/// Alle Gruppen einer Kategorie, jedes Foto mit seiner Begründung.
/// Testoberfläche aus Phase 1, noch ohne Auswahl und Prüfkorb.
struct SuggestionListView: View {
    @Environment(LibraryModel.self) private var library
    let category: SuggestionCategory

    var body: some View {
        let groups = library.results.groups(in: category)
        List(groups) { group in
            SuggestionGroupRow(group: group)
        }
        .navigationTitle(Text(category.title))
    }
}

private struct SuggestionGroupRow: View {
    let group: SuggestionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.small) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: KireiTheme.Spacing.medium) {
                    ForEach(group.items) { item in
                        SuggestionItemCell(item: item)
                    }
                }
                .padding(.vertical, KireiTheme.Spacing.xSmall)
            }
            if group.estimatedSavings > 0 {
                Text("about \(group.estimatedSavings.formatted(.byteCount(style: .file)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SuggestionItemCell: View {
    @Environment(LibraryModel.self) private var library
    let item: SuggestionItem
    @State private var thumbnail: Thumbnail?

    private static let width: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) {
            PhotoTile(thumbnail: thumbnail)
                .frame(width: Self.width, height: Self.width)
                .opacity(item.role == .keep ? 1 : 0.85)

            (item.role == .keep ? Text("Keep") : Text("Suggested"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.role == .keep ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            if item.isPreselected {
                Text("Preselected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(item.reasons, id: \.self) { reason in
                Text(reason.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .task(id: item.assetID) {
            thumbnail = await library.thumbnail(for: item.assetID)
        }
    }
}
