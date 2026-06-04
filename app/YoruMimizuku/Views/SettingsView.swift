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
                .font(.title3).bold()
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
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? theme.accent.opacity(0.16) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appearance:
            AppearanceSettingsView()
        case .display:
            DisplaySettingsContentView()
        }
    }
}

/// Categories shown in the settings sidebar.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "配色"
        case .display: return "表示"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .display: return "rectangle.grid.1x2"
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
                        .font(.caption)
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
            .font(.headline)
            .foregroundStyle(theme.primaryText)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("randoma11y の URL")
                .font(.caption)
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
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プレビュー")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text("YoruMimizuku")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Text("いまどうしてる? — あいうえお Aa 123")
                    .font(.callout)
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

// MARK: - Display

/// Display settings: choose how densely timeline posts are rendered.
private struct DisplaySettingsContentView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("表示")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("表示密度")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Picker("表示密度", selection: $displaySettings.density) {
                        Text("コンパクト").tag(DisplayDensity.compact)
                        Text("ゆとり").tag(DisplayDensity.comfortable)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("コンパクトは Yorufukurou 風の密なレイアウト、ゆとりはアバターやサムネイル、アクション数を表示します。")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
