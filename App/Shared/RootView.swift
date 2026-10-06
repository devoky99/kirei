import KireiCore
import SwiftUI

/// Startpunkt auf allen Geräten. Phase 2 ersetzt das durch Seitenleiste und Bilanz.
struct RootView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Library"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.access {
        case .notDetermined:
            AccessIntroView()
        case .denied, .restricted:
            AccessDeniedView()
        case .limited, .full:
            LibraryGridView()
        }
    }
}
