import SwiftUI
import YoruMimizukuKit

/// The 表示 menu's ⌘1…⌘9 (the first nine sidebar rows of the key window) and the
/// 投稿 menu (actions on the post focused in the key window's timeline). Both are
/// disabled when no main window is key, e.g. while Settings is in front.
struct WorkspaceCommands: Commands {
    @FocusedObject private var workspace: WorkspaceModel?
    @FocusedValue(\.postActions) private var post

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            if let workspace {
                ForEach(Array(workspace.shortcutTabs.enumerated()), id: \.offset) { index, tab in
                    Button(workspace.title(for: tab)) { workspace.selection = tab }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        CommandMenu("投稿") {
            // Without a focused post in a key main window there is nothing to act on.
            Group {
                Button("返信") { post?.reply() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(post?.isReposted == true ? "リポストを取り消す" : "リポスト") { post?.repost() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("引用") { post?.quote() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button(post?.isLiked == true ? "いいねを取り消す" : "いいね") { post?.like() }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("リンクをコピー") { post?.copyLink() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("ブラウザで開く") { post?.openInBrowser() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            .disabled(post == nil)
        }
    }
}

/// The focused timeline post's actions, published by the timeline column's
/// `FeedView` so the 投稿 menu acts on the post j/k (or a click) last focused.
struct PostActions {
    let isLiked: Bool
    let isReposted: Bool
    let reply: @MainActor () -> Void
    let repost: @MainActor () -> Void
    let quote: @MainActor () -> Void
    let like: @MainActor () -> Void
    let copyLink: @MainActor () -> Void
    let openInBrowser: @MainActor () -> Void
}

private struct PostActionsKey: FocusedValueKey {
    typealias Value = PostActions
}

extension FocusedValues {
    var postActions: PostActions? {
        get { self[PostActionsKey.self] }
        set { self[PostActionsKey.self] = newValue }
    }
}
