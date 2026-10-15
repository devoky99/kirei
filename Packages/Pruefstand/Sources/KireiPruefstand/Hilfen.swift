import CoreGraphics
import Foundation
import KireiCore

/// Schreibt sofort, auch wenn die Ausgabe in eine Datei oder Pipe geht.
/// Ersetzt im Prüfstand das gepufferte `print` der Standardbibliothek.
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let text = items.map { String(describing: $0) }.joined(separator: separator) + terminator
    FileHandle.standardOutput.write(Data(text.utf8))
}

/// Zahlen mit deutschem Komma.
enum Zahl {
    static func komma(_ value: Double, stellen: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(stellen)).locale(Locale(identifier: "de_DE")))
    }

    static func komma(_ value: Float, stellen: Int = 2) -> String {
        komma(Double(value), stellen: stellen)
    }

    static func prozent(_ value: Double) -> String {
        komma(value * 100, stellen: 1) + " %"
    }

    static func ganz(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")))
    }
}

/// Begründungen auf Deutsch, wie in der App.
enum Gruende {
    static func text(_ reason: SuggestionReason) -> String {
        switch reason {
        case .bestOfGroup: "Bestes Foto der Gruppe"
        case .sharpest: "Am schärfsten"
        case .eyesOpen: "Augen offen"
        case .original: "Wird als Original behalten"
        case .burstSelection: "In der Serie ausgewählt"
        case .protected(.favorite): "Favorit"
        case .protected(.edited): "Bearbeitet"
        case .protected(.inAlbum): "In einem Album"
        case .exactCopy: "Exakte Kopie"
        case .nearlyIdentical: "Fast gleich wie das behaltene Foto"
        case .lessSharp: "Unschärfer als das behaltene Foto"
        case .eyesClosed: "Augen geschlossen"
        case .unselectedBurstFrame: "In der Serie nicht ausgewählt"
        case .blurry: "Wirkt unscharf"
        case .screenshot(let days): "Bildschirmfoto von vor \(days) Tagen"
        case .screenRecording(let seconds): "Bildschirmaufnahme, \(seconds) s"
        case .largeVideo(let bytes): "Etwa \(bytes.formatted(.byteCount(style: .file)))"
        }
    }

    static func text(_ reasons: [SuggestionReason]) -> String {
        reasons.map(text).joined(separator: ", ")
    }
}

/// Einfache CSV mit Semikolon, wie Numbers und Excel sie in Deutschland öffnen.
enum CSV {
    static func feld(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func zeile(_ felder: [String]) -> String {
        felder.map(feld).joined(separator: ";")
    }

    /// Liest Zeilen und Felder, auch in Anführungszeichen. Erkennt Komma oder Semikolon.
    static func lesen(_ text: String) -> [[String]] {
        let characters = Array(text)
        let firstLine = characters.prefix { $0 != "\n" && $0 != "\r\n" }
        let separator: Character = firstLine.contains(";") ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            index += 1
            if quoted {
                if character == "\"" {
                    if index < characters.count && characters[index] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

/// Testbilder ohne Dateien, für den Selbsttest.
enum Testbilder {
    static func zeichnen(size: Int = 512, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }

    static func schachbrett() -> CGImage? {
        zeichnen { context in
            context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1))
            for row in 0..<16 {
                for column in 0..<16 where (row + column) % 2 == 0 {
                    context.fill(CGRect(x: column * 32, y: row * 32, width: 32, height: 32))
                }
            }
        }
    }

    static func verlauf() -> CGImage? {
        zeichnen { context in
            for column in 0..<512 {
                let value = CGFloat(column) / 511
                context.setFillColor(CGColor(red: value, green: 0.5, blue: 1 - value, alpha: 1))
                context.fill(CGRect(x: column, y: 0, width: 1, height: 512))
            }
        }
    }
}
