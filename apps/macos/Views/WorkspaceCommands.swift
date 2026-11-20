import SwiftUI
import YoruMimizukuKit

/// The menus of the desktop prototype: 表示 (⌘1…⌘9 for the first nine sidebar
/// rows, 新着を読み込む), 編集 (検索) and 投稿 (actions on the post focused in the
/// key window's timeline). They are disabled when no main window is key, e.g.
/// while Settings is in front. The sidebar toggle (⌃⌘S) is `SidebarCommands`.
struct WorkspaceCommands: Commands {
    @FocusedObject private var workspace: WorkspaceModel?
    @FocusedValue(\.postActions) private var post
    @FocusedValue(\.windowActions) private var window

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            if let workspace {
                ForEach(Array(workspace.shortcutTabs.enumerated()), id: \.offset) { index, tab in
                    Button(workspace.title(for: tab)) { workspace.selection = tab }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            Divider()
            Button("新着を読み込む") { window?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(window == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("検索") { window?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(window == nil)
        }

        CommandMenu("投稿") {
            // Without a focused post in a key main window there is nothing to act on.
            Group {
                Button("返信") { post?.reply() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button(post?.isReposted == true ? "リポストを取り消す" : "リポスト") { post?.repost() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("引用して投稿") { post?.quote() }
                // Like is the plain L key in the timeline, as in the prototype; a
                // plain-key menu equivalent would also fire while typing.
                Button(post?.isLiked == true ? "いいねを取り消す（L）" : "いいね（L）") { post?.like() }
                Divider()
                Button("リンクをコピー") { post?.copyLink() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .disabled(post == nil)
            if let post, let lists = post.listMembership, let authorDID = post.authorDID {
                Divider()
                ListMembershipMenu(context: lists, actorDID: authorDID, handle: post.authorHandle)
            }
        }
    }
}

/// The focused timeline post's actions, published by the timeline column's
/// `FeedView` so the 投稿 menu acts on the post j/k (or a click) last focused.
struct PostActions {
    let isLiked: Bool
    let isReposted: Bool
    let authorDID: String?
    let authorHandle: String
    /// For the "リストに追加" submenu; nil where lists are unavailable.
    let listMembership: ListMembershipContext?
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

/// The key window's timeline-level actions for the 表示 and 編集 menus.
struct WindowActions {
    let reload: @MainActor () -> Void
    let focusSearch: @MainActor () -> Void
}

private struct WindowActionsKey: FocusedValueKey {
    typealias Value = WindowActions
}

extension FocusedValues {
    var windowActions: WindowActions? {
        get { self[WindowActionsKey.self] }
        set { self[WindowActionsKey.self] = newValue }
    }
}
