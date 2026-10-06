import Foundation
import KireiCore

// Prüfstand, Stand Phase 0: liest einen Ordner mit Testbildern so, wie der
// Kern später die Mediathek liest, und misst die Zeit für die Vorschaubilder.
// Ab Phase 1 kommen die markierten Paare und die Trefferquote dazu.

let arguments = Array(CommandLine.arguments.dropFirst())

guard let path = arguments.first else {
    print("""
    Aufruf: swift run --package-path Packages/Pruefstand kirei-pruefstand <Ordner>

    Der Ordner enthält Testbilder (JPEG, HEIC, PNG). Er bleibt lokal und
    gehört nicht ins Repo.
    """)
    exit(64)
}

let folder = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
let source = FolderPhotoSource(folder: folder)

let clock = ContinuousClock()
let start = clock.now

let records = try await source.fetchRecords()
let listed = clock.now

var loaded = 0
for record in records {
    if await source.thumbnail(for: record.id, maxPixelSize: ScanPolicy.gridThumbnailPixelSize) != nil {
        loaded += 1
    }
}
let finished = clock.now

let thumbnailTime = finished - listed
let perImage = records.isEmpty ? Duration.zero : thumbnailTime / records.count

print("Ordner:          \(folder.path)")
print("Bilder gefunden: \(records.count)")
print("Vorschau geladen: \(loaded)")
print("Einlesen:        \((listed - start).formatted(.units(allowed: [.seconds, .milliseconds])))")
print("Vorschaubilder:  \(thumbnailTime.formatted(.units(allowed: [.seconds, .milliseconds])))")
print("Pro Bild:        \(perImage.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))")
