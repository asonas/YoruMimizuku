import SwiftUI
import YoruMimizukuKit

/// Sheet for creating or editing a saved filter: a name field and a raw
/// `searchPosts` query field. Save is disabled until the query is non-blank; a
/// blank name falls back to the query. The caller decides whether the submitted
/// name/query create a new filter or update an existing one.
struct FilterEditorView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    /// `isEditing` only selects the heading/button labels (create vs edit); the
    /// initial `name`/`query` and the `onSubmit` callback carry all the data.
    let isEditing: Bool
    /// Called with the resolved (trimmed, name-fallback-applied) name and query.
    let onSubmit: (_ name: String, _ query: String) -> Void

    @State private var name: String
    @State private var query: String

    init(name: String, query: String, isEditing: Bool, onSubmit: @escaping (String, String) -> Void) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _name = State(initialValue: name)
        _query = State(initialValue: query)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "フィルターを編集" : "フィルターを追加")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("名前").font(.caption).foregroundStyle(theme.secondaryText)
                TextField("例: Swift", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("検索クエリ").font(.caption).foregroundStyle(theme.secondaryText)
                TextField("例: #swift from:alice.bsky.social", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("ハッシュタグ・from:ユーザー名・キーワードなどを指定できます")
                    .font(.caption2).foregroundStyle(theme.tertiaryText)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button(isEditing ? "保存" : "追加") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(trimmedName.isEmpty ? trimmedQuery : trimmedName, trimmedQuery)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.background)
    }
}
