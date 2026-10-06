import KireiUI
import SwiftUI

/// Erklärt vor der Systemabfrage, wozu Kirei die Fotos braucht.
///
/// Der Knopf heißt „Weiter“ und ahmt den Systemdialog nicht nach (Regel 5.1.1).
struct AccessIntroView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: KireiTheme.Spacing.large) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Tidy up your photos")
                .font(.title2.weight(.semibold))

            Text("Kirei looks for duplicates, similar shots and blurry photos. Everything stays on your device, and nothing is deleted without you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                Task { await library.requestAccess() }
            } label: {
                Text("Continue")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(KireiTheme.Spacing.xLarge)
        .frame(maxWidth: KireiTheme.Layout.readableWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Ruhiger Hinweis, wenn der Zugriff abgelehnt wurde. Kein Druck, nur der Weg.
struct AccessDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: KireiTheme.Spacing.large) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Photo access is off")
                .font(.title2.weight(.semibold))

            Text("You can turn it on in Settings. Kirei only reads previews on this device and never sends anything.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let url = PlatformSettings.photoPrivacySettingsURL {
                Button {
                    openURL(url)
                } label: {
                    Text("Open Settings")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(KireiTheme.Spacing.xLarge)
        .frame(maxWidth: KireiTheme.Layout.readableWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
