#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// DEBUG-only design catalog: real components rendered from CatalogFixtures.
/// Sidebar = component groups; detail = every variant of the selection with a
/// caption naming the variant and the DesignMetrics constants it exercises.
struct DesignCatalogView: View {
    @StateObject private var theme: ThemeStore
    @StateObject private var display: DisplaySettingsStore
    @State private var selection: String?

    init() {
        // Throwaway defaults suite: toggling density/theme in the catalog must
        // not touch the real app settings.
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizuku.catalog")!
        _theme = StateObject(wrappedValue: ThemeStore(defaults: sandbox))
        _display = StateObject(wrappedValue: DisplaySettingsStore(defaults: sandbox))
    }

    private var componentNames: [String] {
        var seen = [String]()
        for v in CatalogVariant.allCases where v.platforms.contains(.macOS) {
            if !seen.contains(v.componentName) { seen.append(v.componentName) }
        }
        return seen
    }

    var body: some View {
        NavigationSplitView {
            List(componentNames, id: \.self, selection: $selection) { Text($0) }
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(CatalogVariant.allCases.filter {
                        $0.componentName == (selection ?? "PostRow")
                            && $0.platforms.contains(.macOS)
                    }) { variant in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variant.id).font(.headline)
                            if !variant.metricsUsed.isEmpty {
                                Text(variant.metricsUsed.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            CatalogRegistry.view(for: variant)
                                .padding(12)
                                .background(theme.background)
                        }
                    }
                }
                .padding(20)
            }
        }
        .environmentObject(theme)
        .environmentObject(display)
        .frame(minWidth: 720, minHeight: 480)
    }
}
#endif
