import KireiUI

/// Alle Aktionen der App an einer Stelle. Jede bekommt Knopf, Kürzel und VoiceOver.
enum AppActions {
    static let refresh = KireiAction(
        id: "refresh",
        title: "Check again",
        systemImage: "arrow.clockwise",
        shortcut: Shortcut(.character("r"), modifiers: .command)
    )
}
