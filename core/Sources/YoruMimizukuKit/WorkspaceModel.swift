import Foundation

/// Identifies a vertical tab in the sidebar. `home` and `notifications` are pinned
/// and always present; each `conversation` is a closable reply-thread tab.
public enum WorkspaceTab: Hashable, Sendable {
    case home
    case notifications
    case conversation(UUID)
}

/// One conversation tab: anchored on a post URI, it owns the `ThreadViewModel`
/// that fetches that post and its immediate parent so the tree can be climbed.
@MainActor
public final class ConversationTab: Identifiable {
    public let id = UUID()
    /// The anchored post's URI; used to de-duplicate tabs for the same post.
    public let anchorID: String
    /// Sidebar title: the anchored author's display name (falls back to handle).
    public let title: String
    /// `@handle` shown as the row's monospaced meta line.
    public let handle: String
    /// A one/two-line snippet of the anchored post body, shown under the title.
    public let subtitle: String
    public let model: ThreadViewModel

    public init(anchor: PostDisplay, model: ThreadViewModel) {
        self.anchorID = anchor.id
        let trimmedName = anchor.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedName.isEmpty ? "@\(anchor.authorHandle)" : trimmedName
        self.handle = "@\(anchor.authorHandle)"
        self.subtitle = anchor.body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
    }
}

/// Holds the sidebar's tab state: the pinned home/notifications tabs plus an
/// ordered list of conversation tabs that open below them. Opening a post's
/// parent appends a new conversation tab and selects it; closing a conversation
/// falls back to a neighbor (never to a pinned tab being removed).
@MainActor
public final class WorkspaceModel: ObservableObject {
    @Published public private(set) var conversations: [ConversationTab] = []
    @Published public var selection: WorkspaceTab = .home

    private let makeThreadModel: @MainActor (String) -> ThreadViewModel

    public init(makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel) {
        self.makeThreadModel = makeThreadModel
    }

    /// Open `post` in a conversation tab. If a tab for the same post already
    /// exists it is re-selected rather than duplicated.
    public func openConversation(_ post: PostDisplay) {
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
    public func closeConversation(_ id: UUID) {
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

    public func conversation(id: UUID) -> ConversationTab? {
        conversations.first { $0.id == id }
    }

    /// All tabs in display order: the two pinned tabs followed by the open
    /// conversations. Drives the Cmd-Shift-J/K cycling shortcuts.
    public var orderedTabs: [WorkspaceTab] {
        [.home, .notifications] + conversations.map { .conversation($0.id) }
    }

    /// Select the next tab in display order, wrapping past the last back to home.
    public func selectNextTab() { cycleSelection(by: 1) }

    /// Select the previous tab in display order, wrapping past home to the last.
    public func selectPreviousTab() { cycleSelection(by: -1) }

    private func cycleSelection(by offset: Int) {
        let tabs = orderedTabs
        guard let index = tabs.firstIndex(of: selection) else {
            selection = .home
            return
        }
        selection = tabs[(index + offset + tabs.count) % tabs.count]
    }
}
