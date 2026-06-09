import SwiftUI
import YoruMimizukuKit

/// The settings screen: a left sidebar listing categories and a right pane that
/// shows the controls for the selected category. Currently exposes appearance
/// (randoma11y theming) and display (timeline density) settings.
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var selection: SettingsTab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(theme.divider)
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(theme.divider)
                detail
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(theme.background)
    }

    private var titleBar: some View {
        HStack {
            Text("設定")
                .font(.app(.title3, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button("閉じる") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190, alignment: .leading)
        .background(theme.surface.opacity(0.4))
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Label(tab.title, systemImage: tab.icon)
                .font(.app(.callout, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? theme.accent.opacity(0.16) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appearance:
            AppearanceSettingsView()
        case .font:
            FontSettingsContentView()
        case .display:
            DisplaySettingsContentView()
        case .update:
            UpdateSettingsView()
        }
    }
}

/// Categories shown in the settings sidebar.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case font
    case display
    case update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "配色"
        case .font: return "フォント"
        case .display: return "表示"
        case .update: return "アップデート"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .font: return "textformat"
        case .display: return "rectangle.grid.1x2"
        case .update: return "arrow.down.circle"
        }
    }
}

// MARK: - Appearance

/// Theme settings: paste a randoma11y.com URL to recolor the UI, preview the
/// resulting background/text pair, and swap which color is which.
private struct AppearanceSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore

    @State private var urlInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("配色")
                urlField
                if let errorMessage {
                    Text(errorMessage)
                        .font(.app(.caption))
                        .foregroundStyle(.red)
                }
                preview
                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { urlInput = theme.sourceURL }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(.headline))
            .foregroundStyle(theme.primaryText)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("randoma11y の URL")
                .font(.app(.caption))
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 8) {
                TextField("https://randoma11y.com/%2344403c/%23fafaf9", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(apply)
                Button("適用", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("1色目を背景、2色目を文字色として適用します。")
                .font(.app(.caption2))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プレビュー")
                .font(.app(.caption))
                .foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text("YoruMimizuku")
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)
                Text("いまどうしてる? — あいうえお Aa 123")
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                theme.swap()
            } label: {
                Label("背景色と文字色を入れ替える", systemImage: "arrow.left.arrow.right")
            }
            Spacer()
            Button("デフォルトに戻す") {
                theme.reset()
                urlInput = ""
                errorMessage = nil
            }
        }
    }

    private func apply() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try theme.apply(urlString: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? RandomA11yParseError {
        case .invalidURL:
            return "URL の形式が正しくありません。"
        case .wrongHost:
            return "randoma11y.com の URL を入力してください。"
        case .missingColors:
            return "URL に色が 2 つ含まれていません。"
        case .unsupportedColor(let value):
            return "対応していない色の指定です: \(value)"
        case .none:
            return "配色を適用できませんでした。"
        }
    }
}

// MARK: - Font

/// Font settings: pick any installed font family for the whole UI, preview it,
/// and reset to the default. The chosen family is persisted by `FontSettingsStore`.
private struct FontSettingsContentView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var fontSettings: FontSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("フォント")
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("フォントファミリ")
                        .font(.app(.caption))
                        .foregroundStyle(theme.secondaryText)
                    HStack(spacing: 8) {
                        familyPicker
                        Button("デフォルトに戻す") { fontSettings.reset() }
                            .disabled(fontSettings.isDefault)
                    }
                    Text("UI 全体のテキストに適用されます。等幅が必要な箇所(数値や @handle など)はシステムフォントのままです。")
                        .font(.app(.caption2))
                        .foregroundStyle(theme.secondaryText)
                }

                sizeControl

                preview
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var familyPicker: some View {
        Picker("フォントファミリ", selection: $fontSettings.family) {
            ForEach(fontSettings.availableFamilies, id: \.self) { name in
                Text(name)
                    .font(.custom(name, size: 13))
                    .tag(name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var sizeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("フォントサイズ(本文)")
                    .font(.app(.caption))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Stepper(
                    value: $fontSettings.baseSize,
                    in: Double(AppTypography.minBaseSize)...Double(AppTypography.maxBaseSize),
                    step: 1
                ) {
                    Text("\(Int(fontSettings.baseSize.rounded())) pt")
                        .font(.app(.callout))
                        .foregroundStyle(theme.primaryText)
                        .monospacedDigit()
                }
            }
            Text("本文の大きさを指定します。見出しや補助テキストはこれに比例して拡大・縮小します。")
                .font(.app(.caption2))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プレビュー")
                .font(.app(.caption))
                .foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text(fontSettings.family)
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)
                Text("吾輩は猫である。名前はまだ無い。The quick brown fox 0123456789")
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.surface.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Display

/// Display settings: choose how densely timeline posts are rendered.
private struct DisplaySettingsContentView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("表示")
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("表示密度")
                        .font(.app(.caption))
                        .foregroundStyle(theme.secondaryText)
                    Picker("表示密度", selection: $displaySettings.density) {
                        Text("コンパクト").tag(DisplayDensity.compact)
                        Text("ゆとり").tag(DisplayDensity.comfortable)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("コンパクトは Yorufukurou 風の密なレイアウト、ゆとりはアバターやサムネイル、アクション数を表示します。")
                        .font(.app(.caption2))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
