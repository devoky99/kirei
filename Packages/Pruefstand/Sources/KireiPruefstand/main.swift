import Foundation

// Prüfstand für Kirei: misst den Analyse-Kern auf dem Mac mit Testbildern
// statt der Mediathek. Testbilder bleiben lokal und gehören nie ins Repo.

enum Hilfe {
    static let text = """
Prüfstand für Kirei

  kirei-pruefstand selbsttest
      Prüft, ob die Vision-Analyse auf diesem Mac läuft.

  kirei-pruefstand beispiel <Ordner>
      Legt erzeugte Beispielbilder an, um die Befehle auszuprobieren.

  kirei-pruefstand messen <Ordner>
      Misst die Zeit pro Foto und rechnet auf 20.000 Fotos hoch.

  kirei-pruefstand kalibrieren <Ordner>
      Schlägt Schwellen aus markierten Beispielen vor. Erwartet Unterordner:
        aehnlich/<serie>/       Fotos, die als fast gleich gelten sollen
        verschieden/<serie>/    ähnliche Motive, die getrennt bleiben sollen
        unscharf/  scharf/      einzelne Fotos
        augen_zu/  augen_offen/ Fotos mit Gesichtern

  kirei-pruefstand vorschlaege <Ordner>
      Läuft wie die App über den Ordner und schreibt die Vorschläge
      „ähnlich“ zum Prüfen in kirei-vorschlaege.html und .csv.

  kirei-pruefstand auswerten <Datei.csv>
      Zählt die Urteile und prüft Prüfpunkt 1 (mindestens 1.000 geprüfte
      Vorschläge, Untergrenze der Trefferquote mindestens 98 %).

Aufruf aus dem Repo:
  swift run -c release --package-path Packages/Pruefstand kirei-pruefstand <Befehl>
"""

    /// Der Ordner aus dem zweiten Argument, sonst Abbruch mit Hinweis.
    static func ordner(_ arguments: [String]) -> URL {
        guard arguments.count >= 2 else {
            print(text)
            exit(64)
        }
        let url = URL(filePath: (arguments[1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            print("Ordner nicht gefunden: \(url.path)")
            exit(66)
        }
        return url.standardizedFileURL
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

let status: Int32
switch arguments.first {
case "selbsttest":
    status = await Selbsttest.run()
case "beispiel":
    guard arguments.count >= 2 else {
        print(Hilfe.text)
        exit(64)
    }
    let target = URL(filePath: (arguments[1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    status = Beispiel.run(folder: target.standardizedFileURL)
case "messen":
    status = await Messen.run(folder: Hilfe.ordner(arguments))
case "kalibrieren":
    status = await Kalibrieren.run(folder: Hilfe.ordner(arguments))
case "vorschlaege":
    status = await Vorschlaege.run(folder: Hilfe.ordner(arguments))
case "auswerten":
    guard arguments.count >= 2 else {
        print(Hilfe.text)
        exit(64)
    }
    status = Auswerten.run(file: URL(filePath: (arguments[1] as NSString).expandingTildeInPath))
default:
    print(Hilfe.text)
    status = arguments.isEmpty ? 0 : 64
}
exit(status)
