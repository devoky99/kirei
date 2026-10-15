#if DEBUG
import CoreTransferable
import KireiCore
import KireiUI
import SwiftUI
import UniformTypeIdentifiers

// Prüfmodus für Prüfpunkt 1. Nur in Entwicklungs-Builds, nie im App Store.
// Texte deshalb nur auf Deutsch und nicht im String Catalog.

/// Merkt sich die Urteile und den aktuellen Vorschlag.
@MainActor
@Observable
final class ReviewModel {
    private(set) var log: ReviewLog
    private(set) var index = 0
    private let store: ReviewStore?

    init(store: ReviewStore? = try? .standard()) {
        self.store = store
        self.log = store?.load() ?? ReviewLog()
    }

    func start(_ pairs: [ReviewPair]) {
        index = log.firstOpenIndex(in: pairs)
    }

    func judge(_ verdict: ReviewVerdict, _ pair: ReviewPair, in pairs: [ReviewPair]) {
        log[pair] = verdict
        try? store?.save(log)
        index = min(index + 1, max(0, pairs.count - 1))
    }

    func move(by step: Int, in pairs: [ReviewPair]) {
        index = min(max(0, index + step), max(0, pairs.count - 1))
    }
}

struct ReviewView: View {
    @Environment(LibraryModel.self) private var library
    @State private var model = ReviewModel()

    private static let exportName: String = "kirei-pruefung.csv"

    var body: some View {
        let pairs = ReviewPair.pairs(from: library.results)
        ScrollView {
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.large) {
                ReviewStatus(estimate: model.log.estimate(for: pairs), total: pairs.count)

                if let metrics = library.results.metrics {
                    MetricsRow(metrics: metrics, photos: library.results.summary.photos)
                } else if library.isScanning {
                    Text(verbatim: "Der Scan läuft noch. Die Messwerte erscheinen danach.")
                        .foregroundStyle(.secondary)
                }

                if pairs.isEmpty {
                    Text(verbatim: "Noch keine Vorschläge „ähnlich“. Erst den Scan abschließen.")
                        .foregroundStyle(.secondary)
                } else {
                    let pair = pairs[min(model.index, pairs.count - 1)]
                    PairView(pair: pair, verdict: model.log[pair], position: model.index + 1, total: pairs.count)
                    ReviewButtons(
                        judge: { model.judge($0, pair, in: pairs) },
                        move: { model.move(by: $0, in: pairs) }
                    )
                }
            }
            .padding(KireiTheme.Spacing.large)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(verbatim: "Prüfmodus"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: ReviewCSV(text: ReviewExport.csv(
                        pairs: pairs,
                        log: model.log,
                        metrics: library.results.metrics,
                        photoCount: library.results.summary.photos
                    )),
                    preview: SharePreview(Self.exportName)
                ) {
                    Label {
                        Text(verbatim: "Urteile exportieren")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(pairs.isEmpty)
            }
        }
        .task(id: pairs.count) {
            model.start(pairs)
        }
    }
}

/// Stand der Prüfung und Prüfpunkt 1.
private struct ReviewStatus: View {
    let estimate: PrecisionEstimate
    let total: Int

    private static let target = 0.98
    private static let minimumCount = 1_000

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.small) {
            Text(verbatim: "Ist das rechte Foto fast gleich wie das linke?")
                .font(.title3.weight(.semibold))
            Text(verbatim: "Geprüft \(estimate.total) von \(total), davon \(estimate.total - estimate.correct) falsch")
            if estimate.total > 0 {
                Text(verbatim: "Trefferquote \(percent(estimate.precision)), Untergrenze \(percent(estimate.lowerBound))")
            }
            if estimate.meets(target: Self.target, minimumCount: Self.minimumCount) {
                Label {
                    Text(verbatim: "Prüfpunkt 1 bestanden")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .foregroundStyle(.tint)
            } else {
                Text(verbatim: openText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var openText: String {
        if estimate.total < Self.minimumCount {
            let missing = Self.minimumCount - estimate.total
            return "Prüfpunkt 1: noch \(missing) Vorschläge bis \(Self.minimumCount), Untergrenze mindestens 98 %"
        }
        return "Prüfpunkt 1: Untergrenze unter 98 %, die Schwelle für „ähnlich“ muss strenger werden"
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}

/// Messwerte für die Zielwerte aus dem Konzept.
private struct MetricsRow: View {
    let metrics: ScanMetrics
    let photos: Int

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) {
            Text(verbatim: "Messwerte des letzten Scans")
                .font(.subheadline.weight(.semibold))
            Text(verbatim: "Erste Ergebnisse nach \(seconds(metrics.firstResultsSeconds)) (Ziel unter 10 s)")
            Text(verbatim: "Analysiert: \(metrics.analyzedInThisRun) Fotos in \(minutes(metrics.analysisSeconds))")
            if let projected = metrics.projectedAnalysisSeconds(for: 20_000) {
                Text(verbatim: "Hochgerechnet auf 20.000 Fotos: \(minutes(projected)) (Ziel unter 10 min)")
            }
            Text(verbatim: "Spitzen-Speicher: \(metrics.peakMemoryBytes / 1_000_000) MB (Ziel unter 300 MB)")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private func minutes(_ value: Double) -> String {
        (value / 60).formatted(.number.precision(.fractionLength(1))) + " min"
    }
}

/// Behaltenes und vorgeschlagenes Foto nebeneinander, groß.
private struct PairView: View {
    let pair: ReviewPair
    let verdict: ReviewVerdict?
    let position: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: KireiTheme.Spacing.medium) {
                ReviewImage(assetID: pair.keep, caption: "Behalten")
                ReviewImage(assetID: pair.suggested, caption: "Vorschlag")
            }
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) {
                Text(verbatim: "Vorschlag \(position) von \(total), Gruppe \(pair.groupNumber)")
                    .font(.subheadline.weight(.semibold))
                ForEach(pair.reasons, id: \.self) { reason in
                    Text(reason.text)
                }
                if let distance = pair.distance {
                    Text(verbatim: "Abstand \(Double(distance).formatted(.number.precision(.fractionLength(3))))")
                }
                if let verdict {
                    Text(verbatim: verdict == .correct ? "Bisher: richtig" : "Bisher: falsch")
                        .foregroundStyle(verdict == .correct ? AnyShapeStyle(.tint) : AnyShapeStyle(.red))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ReviewImage: View {
    @Environment(LibraryModel.self) private var library
    let assetID: AssetID
    let caption: String
    @State private var thumbnail: Thumbnail?

    var body: some View {
        VStack(alignment: .leading, spacing: KireiTheme.Spacing.xSmall) {
            ZStack {
                RoundedRectangle(cornerRadius: KireiTheme.Radius.card, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(decorative: thumbnail.cgImage, scale: 1, orientation: PhotoTile.orientation(thumbnail.orientation))
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: KireiTheme.Radius.card, style: .continuous))
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            Text(verbatim: caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: caption))
        .task(id: assetID) {
            thumbnail = nil
            thumbnail = await library.thumbnail(for: assetID, pixelSize: 1_200, mode: .fit)
        }
    }
}

/// Richtig, falsch, zurück, weiter. Auf dem Mac und am iPad mit Tastatur: R, F, Pfeiltasten.
private struct ReviewButtons: View {
    let judge: (ReviewVerdict) -> Void
    let move: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KireiTheme.Spacing.medium) { buttons }
            VStack(alignment: .leading, spacing: KireiTheme.Spacing.small) { buttons }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var buttons: some View {
        Button { judge(.correct) } label: {
            Label { Text(verbatim: "Richtig (R)") } icon: { Image(systemName: "checkmark") }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("r", modifiers: [])

        Button { judge(.wrong) } label: {
            Label { Text(verbatim: "Falsch (F)") } icon: { Image(systemName: "xmark") }
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("f", modifiers: [])

        Button { move(-1) } label: {
            Label { Text(verbatim: "Zurück") } icon: { Image(systemName: "chevron.left") }
        }
        .keyboardShortcut(.leftArrow, modifiers: [])

        Button { move(1) } label: {
            Label { Text(verbatim: "Weiter") } icon: { Image(systemName: "chevron.right") }
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
    }
}

/// Die Urteile als CSV-Datei zum Teilen, etwa per AirDrop oder Mail.
struct ReviewCSV: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in
            Data(csv.text.utf8)
        }
        .suggestedFileName("kirei-pruefung.csv")
    }
}
#endif
