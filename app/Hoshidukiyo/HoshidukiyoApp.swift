import SwiftUI

@main
struct HoshidukiyoApp: App {
    init() {
        MetricsSubscriber.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(DebugPerfOverlay())
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}
