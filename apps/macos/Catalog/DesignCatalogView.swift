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
    @State private var columnWidth: Double = 560
    @State private var showMetricsCaptions = true

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

                    themeMenu

                    Slider(value: $columnWidth, in: 320...900) { Text("幅") }
                        .frame(width: 180)
                    Text("\(Int(columnWidth))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Toggle("余白注記", isOn: $showMetricsCaptions)
                }
            }
        }
        .environmentObject(theme)
        .environmentObject(display)
        .frame(minWidth: 720, minHeight: 480)
    }

    /// Named randoma11y presets applied through the sandboxed `ThemeStore`'s own
    /// `apply(urlString:)`/`reset()`/`swap()` API — the same calls `SettingsView`'s
    /// 外観 tab makes. SettingsView's own theme control is a freeform URL text
    /// field (paste a randoma11y.com link), which doesn't fit a toolbar item
    /// group, so this substitutes a small fixed set of presets plus the swap
    /// action to exercise the same underlying mechanism from the toolbar.
    private static let themePresets: [(name: String, url: String)] = [
        ("既定", ""),
        ("ダーク", "https://randoma11y.com/%23101418/%23e8edf2"),
        ("フォレスト", "https://randoma11y.com/%23132018/%23dcefe1"),
        ("プラム", "https://randoma11y.com/%23231226/%23f1e4f7"),
    ]

    private var themeMenu: some View {
        Menu {
            ForEach(Self.themePresets, id: \.name) { preset in
                Button(preset.name) { applyThemePreset(preset.url) }
            }
            Divider()
            Button("背景色と文字色を入れ替える") { theme.swap() }
        } label: {
            Label("テーマ", systemImage: "paintpalette")
        }
    }

    private func applyThemePreset(_ url: String) {
        if url.isEmpty {
            theme.reset()
        } else {
            try? theme.apply(urlString: url)
        }
    }
}
#endif
