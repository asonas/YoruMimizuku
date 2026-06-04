import Foundation
import HoshidukiyoKit

/// Identifies a vertical tab in the sidebar. `home` and `notifications` are pinned
/// and always present; each `conversation` is a closable reply-thread tab.
enum WorkspaceTab: Hashable {
    case home
    case notifications
    case conversation(UUID)
}

/// One conversation tab: anchored on a post URI, it owns the `ThreadViewModel`
/// that fetches that post and its immediate parent so the tree can be climbed.
@MainActor
final class ConversationTab: Identifiable {
    let id = UUID()
    /// The anchored post's URI; used to de-duplicate tabs for the same post.
    let anchorID: String
    /// Short label for the sidebar (the anchored author's handle).
    let title: String
    let model: ThreadViewModel

    init(anchor: PostDisplay, model: ThreadViewModel) {
        self.anchorID = anchor.id
        self.title = "@\(anchor.authorHandle)"
        self.model = model
    }
}

/// Holds the sidebar's tab state: the pinned home/notifications tabs plus an
/// ordered list of conversation tabs that open below them. Opening a post's
/// parent appends a new conversation tab and selects it; closing a conversation
/// falls back to a neighbor (never to a pinned tab being removed).
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var conversations: [ConversationTab] = []
    @Published var selection: WorkspaceTab = .home

    private let makeThreadModel: @MainActor (String) -> ThreadViewModel

    init(makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel) {
        self.makeThreadModel = makeThreadModel
    }

    /// Open `post` in a conversation tab. If a tab for the same post already
    /// exists it is re-selected rather than duplicated.
    func openConversation(_ post: PostDisplay) {
        if let existing = conversations.first(where: { $0.anchorID == post.id }) {
            selection = .conversation(existing.id)
            return
        }
        let tab = ConversationTab(anchor: post, model: makeThreadModel(post.id))
        conversations.append(tab)
        selection = .conversation(tab.id)
    }

    /// Close a conversation tab. When the closed tab was selected, select the
    /// adjacent conversation if any, otherwise fall back to home.
    func closeConversation(_ id: UUID) {
        let wasSelected = selection == .conversation(id)
        let index = conversations.firstIndex { $0.id == id }
        conversations.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !conversations.isEmpty {
            selection = .conversation(conversations[min(index, conversations.count - 1)].id)
        } else {
            selection = .home
        }
    }

    func conversation(id: UUID) -> ConversationTab? {
        conversations.first { $0.id == id }
    }
}
