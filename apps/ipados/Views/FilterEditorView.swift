import SwiftUI
import YoruMimizukuKit

/// Sheet for creating or editing a structured filter: a name, an AND/OR selector,
/// and a list of typed condition rows (keyword / user / hashtag / mention). Save is
/// disabled until at least one row expands to a usable query. The caller decides
/// whether the submitted values create a new filter or update an existing one.
///
/// Mirrors the macOS `FilterEditorView` but uses an iPad-native `NavigationStack`
/// + `Form` + toolbar presentation (like `ComposerView`) instead of the macOS
/// fixed-size `VStack` sheet.
struct FilterEditorView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    let onSubmit: (_ name: String, _ terms: [FilterTerm], _ combinator: FilterCombinator) -> Void

    @State private var name: String
    @State private var combinator: FilterCombinator
    @State private var terms: [FilterTerm]

    init(
        name: String,
        terms: [FilterTerm],
        combinator: FilterCombinator,
        isEditing: Bool,
        onSubmit: @escaping (String, [FilterTerm], FilterCombinator) -> Void
    ) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _name = State(initialValue: name)
        _combinator = State(initialValue: combinator)
        // Always show at least one editable row.
        _terms = State(initialValue: terms.isEmpty ? [FilterTerm(kind: .keyword, value: "")] : terms)
    }

    private var canSave: Bool {
        !SavedFilter(name: "", terms: terms, combinator: combinator).subqueries.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: Swift界隈", text: $name)
                        .textInputAutocapitalization(.never)
                }

                Section("結合") {
                    Picker("結合", selection: $combinator) {
                        Text("すべて満たす（AND）").tag(FilterCombinator.and)
                        Text("いずれか（OR）").tag(FilterCombinator.or)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("条件") {
                    ForEach($terms) { $term in
                        VStack(spacing: 8) {
                            HStack {
                                Picker("種別", selection: $term.kind) {
                                    Text("キーワード").tag(FilterTermKind.keyword)
                                    Text("ユーザー").tag(FilterTermKind.user)
                                    Text("ハッシュタグ").tag(FilterTermKind.hashtag)
                                    Text("メンション").tag(FilterTermKind.mention)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                Spacer()
                                Button {
                                    terms.removeAll { $0.id == term.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.tertiaryText)
                                .disabled(terms.count <= 1)
                            }
                            TextField(placeholder(for: term.kind), text: $term.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }

                    Button {
                        terms.append(FilterTerm(kind: .keyword, value: ""))
                    } label: {
                        Label("条件を追加", systemImage: "plus")
                    }
                    .foregroundStyle(theme.accent)
                }
            }
            .navigationTitle(isEditing ? "フィルターを編集" : "フィルターを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "追加") {
                        onSubmit(name, terms, combinator)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func placeholder(for kind: FilterTermKind) -> String {
        switch kind {
        case .keyword: return "キーワード"
        case .user: return "alice.bsky.social"
        case .hashtag: return "swift"
        case .mention: return "bob.bsky.social"
        }
    }
}
