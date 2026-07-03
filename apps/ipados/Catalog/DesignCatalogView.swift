#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// DEBUG-only design catalog: real components rendered from CatalogFixtures.
/// Sidebar = component groups; detail = every variant of the selection with a
/// caption naming the variant and the DesignMetrics constants it exercises.
/// Presented as a sheet from RootView's sidebar (see task-8-brief.md — the iPad
/// app has no settings screen yet, so this lacks the natural home the macOS
/// catalog window has via the Help menu).
///
/// Toolbar scope: the iPad toolbar carries only the density picker, the column
/// width slider, and the caption toggle. The theme preset menu from the macOS
/// catalog is dropped here — three controls already fill a sheet's toolbar at
/// iPad width once you add the picker segments and the slider's numeric
/// readout, and theme swapping is not needed to inspect the width-driven
/// PostRow reflow this catalog exists to check. The width slider itself is
/// kept (not dropped, unlike the brief's fallback suggestion) because the iPad
/// `PostRowView` has the same `contentWidth`-driven reflow as `TimelineListView`
/// (see `regionWidth(forContentWidth:)` in `apps/ipados/Views/PostRowView.swift`),
/// so dragging it is the whole point of inspecting PostRow here.
struct DesignCatalogView: View {
    @StateObject private var theme: ThemeStore
    @StateObject private var display: DisplaySettingsStore
    @State private var selection: String?
    @State private var columnWidth: Double = 560
    @State private var showMetricsCaptions = true

    init() {
        // Throwaway defaults suite: toggling density in the catalog must not
        // touch the real app settings.
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizuku.catalog")!
        _theme = StateObject(wrappedValue: ThemeStore(defaults: sandbox))
        _display = StateObject(wrappedValue: DisplaySettingsStore(defaults: sandbox))
    }

    private var componentNames: [String] {
        var seen = [String]()
        for v in CatalogVariant.allCases where v.platforms.contains(.iPadOS) {
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
                            && $0.platforms.contains(.iPadOS)
                    }) { variant in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variant.id).font(.headline)
                            if showMetricsCaptions && !variant.metricsUsed.isEmpty {
                                Text(variant.metricsUsed.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            CatalogRegistry.view(for: variant, density: display.density, width: CGFloat(columnWidth))
                                .frame(width: columnWidth, alignment: .leading)
                                .padding(12)
                                .background(theme.background)
                        }
                    }
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItemGroup {
                    Picker("密度", selection: $display.density) {
                        Text("A (compact)").tag(DisplayDensity.compact)
                        Text("B (comfortable)").tag(DisplayDensity.comfortable)
                    }
                    .pickerStyle(.segmented)

                    Slider(value: $columnWidth, in: 320...900) { Text("幅") }
                        .frame(width: 140)
                    Text("\(Int(columnWidth))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Toggle("余白注記", isOn: $showMetricsCaptions)
                }
            }
        }
        .environmentObject(theme)
        .environmentObject(display)
    }
}
#endif
