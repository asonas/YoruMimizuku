import Foundation
import YoruMimizukuKit

/// Identifies a vertical tab in the sidebar. `home` and `notifications` are pinned
/// and always present; `filter` is a saved-search subscription; each
/// `conversation` is a closable reply-thread tab.
enum WorkspaceTab: Hashable {
    case home
    case notifications
    case filter(UUID)
    case conversation(UUID)
}

/// One conversation tab: anchored on a post URI, it owns the `ThreadViewModel`
/// that fetches that post and its immediate parent so the tree can be climbed.
@MainActor
final class ConversationTab: Identifiable {
    let id = UUID()
    let anchorID: String
    let title: String
    let handle: String
    let subtitle: String
    let model: ThreadViewModel

    init(anchor: PostDisplay, model: ThreadViewModel) {
        self.anchorID = anchor.id
        let trimmedName = anchor.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedName.isEmpty ? "@\(anchor.authorHandle)" : trimmedName
        self.handle = "@\(anchor.authorHandle)"
        self.subtitle = anchor.body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
    }
}

/// One filter tab: a saved search subscription. `id` mirrors the backing
/// `SavedFilter.id`; it owns a `TimelineViewModel` whose loader runs the search
/// query, so the existing timeline machinery (polling, infinite scroll) is reused
/// unchanged. Editing relabels and, when the query changes, rebuilds the model.
@MainActor
final class FilterTab: Identifiable {
    let id: UUID
    private(set) var title: String
    private(set) var query: String
    private(set) var model: TimelineViewModel
    private let makeModel: @MainActor (String) -> TimelineViewModel

    init(filter: SavedFilter, makeModel: @escaping @MainActor (String) -> TimelineViewModel) {
        self.id = filter.id
        self.title = filter.name
        self.query = filter.query
        self.makeModel = makeModel
        self.model = makeModel(filter.query)
    }

    /// Apply an edited filter: relabel, and if the query changed rebuild the model
    /// so the next appearance loads the new search.
    func apply(_ filter: SavedFilter) {
        title = filter.name
        if filter.query != query {
            query = filter.query
            model = makeModel(filter.query)
        }
    }
}

/// Holds the sidebar's tab state: the pinned home/notifications tabs, the saved
/// filter tabs (persisted via `SavedFilterStore`), and an ordered list of
/// conversation tabs. Opening a post's parent appends a conversation; closing a
/// tab falls back to a neighbor of the same kind, otherwise home.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var filters: [FilterTab] = []
    @Published private(set) var conversations: [ConversationTab] = []
    @Published var selection: WorkspaceTab = .home

    let filterStore: SavedFilterStore
    private let makeThreadModel: @MainActor (String) -> ThreadViewModel
    private let makeFilterModel: @MainActor (String) -> TimelineViewModel

    init(
        filterStore: SavedFilterStore,
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeFilterModel: @escaping @MainActor (String) -> TimelineViewModel
    ) {
        self.filterStore = filterStore
        self.makeThreadModel = makeThreadModel
        self.makeFilterModel = makeFilterModel
        self.filters = filterStore.filters.map { FilterTab(filter: $0, makeModel: makeFilterModel) }
    }

    // MARK: - Filters

    /// Create a filter from raw name/query, append its tab, and select it. No-op
    /// when the query is blank (the store rejects it).
    func addFilter(name: String, query: String) {
        guard let saved = filterStore.add(name: name, query: query) else { return }
        let tab = FilterTab(filter: saved, makeModel: makeFilterModel)
        filters.append(tab)
        selection = .filter(tab.id)
    }

    /// Persist an edited filter and reflect it in its tab (relabel / model swap).
    func updateFilter(_ edited: SavedFilter) {
        filterStore.update(edited)
        guard let tab = filters.first(where: { $0.id == edited.id }) else { return }
        tab.apply(edited)
        filters = filters  // republish so the sidebar picks up the relabel
    }

    /// Delete a filter tab. When the closed tab was selected, select the adjacent
    /// filter if any, otherwise fall back to home.
    func removeFilter(id: UUID) {
        let wasSelected = selection == .filter(id)
        let index = filters.firstIndex { $0.id == id }
        filterStore.remove(id: id)
        filters.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !filters.isEmpty {
            selection = .filter(filters[min(index, filters.count - 1)].id)
        } else {
            selection = .home
        }
    }

    func filter(id: UUID) -> FilterTab? { filters.first { $0.id == id } }

    /// The backing `SavedFilter` for an id (for the editor); nil if absent.
    func savedFilter(id: UUID) -> SavedFilter? { filterStore.filters.first { $0.id == id } }

    // MARK: - Conversations

    func openConversation(_ post: PostDisplay) {
        if let existing = conversations.first(where: { $0.anchorID == post.id }) {
            selection = .conversation(existing.id)
            return
        }
        let tab = ConversationTab(anchor: post, model: makeThreadModel(post.id))
        conversations.append(tab)
        selection = .conversation(tab.id)
    }

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

    // MARK: - Cycling

    /// All tabs in display order: the two pinned tabs, the filters, then the open
    /// conversations. Drives the Cmd-Shift-J/K cycling shortcuts.
    var orderedTabs: [WorkspaceTab] {
        [.home, .notifications]
            + filters.map { .filter($0.id) }
            + conversations.map { .conversation($0.id) }
    }

    func selectNextTab() { cycleSelection(by: 1) }
    func selectPreviousTab() { cycleSelection(by: -1) }

    private func cycleSelection(by offset: Int) {
        let tabs = orderedTabs
        guard let index = tabs.firstIndex(of: selection) else {
            selection = .home
            return
        }
        selection = tabs[(index + offset + tabs.count) % tabs.count]
    }
}
