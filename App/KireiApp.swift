import KireiCore
import SwiftUI

@main
struct KireiApp: App {
    @State private var library = LibraryModel(source: PhotoKitSource())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 720)
        #endif
    }
}
