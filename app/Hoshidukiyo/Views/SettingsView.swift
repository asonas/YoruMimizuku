import SwiftUI
import HoshidukiyoKit

/// Theme settings: paste a randoma11y.com URL to recolor the UI, preview the
/// resulting background/text pair, and swap which color is which.
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            urlField
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            preview
            actions
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 360)
        .background(theme.background)
        .onAppear { urlInput = theme.sourceURL }
    }

    private var header: some View {
        HStack {
            Text("配色設定")
                .font(.title3).bold()
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button("閉じる") { dismiss() }
        }
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
                Text("Hoshidukiyo")
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
