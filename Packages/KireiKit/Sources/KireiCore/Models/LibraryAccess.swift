/// Stand der Fotoberechtigung, unabhängig von der Plattform.
public enum LibraryAccess: Sendable, Equatable {
    /// Noch nie gefragt.
    case notDetermined
    /// Abgelehnt. Kirei erklärt den Weg in die Einstellungen.
    case denied
    /// Durch Bildschirmzeit oder Verwaltung gesperrt.
    case restricted
    /// „Ausgewählte Fotos“ auf iOS: Kirei sieht nur einen Teil.
    case limited
    /// Voller Zugriff.
    case full

    /// Ob Kirei überhaupt Einträge lesen kann.
    public var canRead: Bool {
        switch self {
        case .limited, .full: true
        case .notDetermined, .denied, .restricted: false
        }
    }
}
