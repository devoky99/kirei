import Foundation

/// Eine Aktion, drei Wege: Geste oder Klick, Tastenkürzel und VoiceOver.
///
/// Jede Aktion wird einmal beschrieben und überall gleich verwendet. So
/// bekommt das iPad mit Tastatur automatisch dieselben Kürzel wie der Mac.
public struct KireiAction: Identifiable, Sendable {
    public let id: String
    /// Titel für Knopf, Menü und VoiceOver.
    public let title: LocalizedStringResource
    /// Name eines SF Symbols.
    public let systemImage: String
    public let shortcut: Shortcut?

    public init(id: String, title: LocalizedStringResource, systemImage: String, shortcut: Shortcut? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
    }
}

/// Tastenkürzel ohne SwiftUI-Typen, damit Aktionen im Kern beschreibbar bleiben.
public struct Shortcut: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case character(Character)
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case space
        case delete
        case escape
        case `return`
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}
