import SwiftUI
import YoruMimizukuKit

/// The iPad settings sheet. Mirrors the macOS settings screen but as a single
/// iPad-native `Form` (not the macOS two-pane): appearance (randoma11y theming),
/// display (timeline density), font (family only — the iPad `AppTypography` has no
/// size control), and notifications (poll interval + unread badges). There is no
/// update tab — the iPad ships via TestFlight, not Sparkle.
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    @EnvironmentObject private var fontSettings: FontSettingsStore
    @EnvironmentObject private var notificationSettings: NotificationSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput = ""
    @State private var appearanceError: String?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                displaySection
                fontSection
                notificationsSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear { urlInput = theme.sourceURL }
        }
    }

    // MARK: - 配色

    @ViewBuilder
    private var appearanceSection: some View {
        Section("配色") {
            VStack(alignment: .leading, spacing: 6) {
                Text("randoma11y の URL")
                    .font(.app(.caption)).foregroundStyle(theme.secondaryText)
                TextField("https://randoma11y.com/…", text: $urlInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(applyTheme)
                Button("適用", action: applyTheme)
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let appearanceError {
                    Text(appearanceError).font(.app(.caption)).foregroundStyle(.red)
                }
                Text("1色目を背景、2色目を文字色として適用します。")
                    .font(.app(.caption2)).foregroundStyle(theme.secondaryText)
            }

            themePreview

            Button {
                theme.swap()
            } label: {
                Label("背景色と文字色を入れ替える", systemImage: "arrow.left.arrow.right")
            }
            Button(role: .destructive) {
                theme.reset()
                urlInput = ""
                appearanceError = nil
            } label: {
                Text("デフォルトに戻す")
            }
        }
    }

    private var themePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YoruMimizuku")
                .font(.app(.headline)).foregroundStyle(theme.primaryText)
            Text("いまどうしてる? — あいうえお Aa 123")
                .font(.app(.callout)).foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func applyTheme() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try theme.apply(urlString: trimmed)
            appearanceError = nil
        } catch {
            appearanceError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? RandomA11yParseError {
        case .invalidURL: return "URL の形式が正しくありません。"
        case .wrongHost: return "randoma11y.com の URL を入力してください。"
        case .missingColors: return "URL に色が 2 つ含まれていません。"
        case .unsupportedColor(let value): return "対応していない色の指定です: \(value)"
        case .none: return "配色を適用できませんでした。"
        }
    }

    // MARK: - 表示

    @ViewBuilder
    private var displaySection: some View {
        Section("表示") {
            Picker("表示密度", selection: $displaySettings.density) {
                Text("コンパクト").tag(DisplayDensity.compact)
                Text("ゆとり").tag(DisplayDensity.comfortable)
            }
            .pickerStyle(.segmented)
            Text("コンパクトは Yorufukurou 風の密なレイアウト、ゆとりはアバターやサムネイル、アクション数を表示します。")
                .font(.app(.caption2)).foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - フォント

    @ViewBuilder
    private var fontSection: some View {
        Section("フォント") {
            Picker("フォントファミリ", selection: $fontSettings.family) {
                ForEach(fontSettings.availableFamilies, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            Button("デフォルトに戻す") { fontSettings.reset() }
                .disabled(fontSettings.isDefault)
            Text("UI 全体のテキストに適用されます。等幅が必要な箇所(数値や @handle など)はシステムフォントのままです。")
                .font(.app(.caption2)).foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - 通知

    @ViewBuilder
    private var notificationsSection: some View {
        Section("通知") {
            Picker("更新間隔", selection: $notificationSettings.pollIntervalSeconds) {
                ForEach(NotificationSettingsStore.intervalChoices, id: \.self) { seconds in
                    Text(Self.intervalLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            Toggle("未読バッジを表示する", isOn: $notificationSettings.showsUnreadBadges)
            Text("ホーム・通知・フィルターの各タブが新着を確認する間隔です。短くするほど早く反映されますが、通信と電力を多く使います。")
                .font(.app(.caption2)).foregroundStyle(theme.secondaryText)
        }
    }

    /// Human label for a polling interval in seconds (e.g. 15→"15秒", 300→"5分").
    private static func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)秒" : "\(seconds / 60)分"
    }
}
