import Foundation

/// Identifies a vertical tab in the sidebar. `home` and `notifications` are pinned
/// and always present; `filter` is a saved-search subscription; each
/// `conversation` is a closable reply-thread tab.
public enum WorkspaceTab: Hashable, Sendable {
    case home
    case notifications
    case filter(UUID)
    case conversation(UUID)
    case author(UUID)
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

    /// Rebuild a tab from a persisted snapshot, restoring its sidebar fields so it
    /// renders before its thread loads.
    public init(saved: SavedConversation, model: ThreadViewModel) {
        self.anchorID = saved.anchorID
        self.title = saved.title
        self.handle = saved.handle
        self.subtitle = saved.subtitle
        self.model = model
    }

    /// The snapshot persisted for this tab.
    var saved: SavedConversation {
        SavedConversation(anchorID: anchorID, title: title, handle: handle, subtitle: subtitle)
    }
}

/// One author tab: a view-only window onto a single user. Anchored on the user's
/// DID (the dedupe key), it owns a `TimelineViewModel` backed by the author feed and
/// a `ProfileHeaderViewModel` for the header. The tab captures the tapped avatar's
/// basics so its header and sidebar row render instantly; the feed and full profile
/// load lazily. Author tabs are ephemeral (never persisted).
@MainActor
public final class AuthorTab: Identifiable {
    public let id = UUID()
    /// The user's DID; used to de-duplicate tabs for the same user.
    public let did: String
    public let handle: String
    public let displayName: String
    public let avatarURL: URL?
    public let model: TimelineViewModel
    public let header: ProfileHeaderViewModel

    public init(
        did: String,
        handle: String,
        displayName: String,
        avatarURL: URL?,
        model: TimelineViewModel,
        header: ProfileHeaderViewModel
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.model = model
        self.header = header
    }

    /// Sidebar title: the display name, falling back to the handle when blank.
    public var title: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "@\(handle)" : trimmed
    }
}

/// One filter tab: a saved structured search. `id` mirrors the backing
/// `SavedFilter.id`; it owns a `TimelineViewModel` whose loader runs the filter's
/// expanded subqueries, reusing the timeline machinery unchanged. Editing relabels
/// and, when the expanded queries change, rebuilds the model.
@MainActor
public final class FilterTab: Identifiable {
    public let id: UUID
    public private(set) var title: String
    public private(set) var filter: SavedFilter
    public private(set) var model: TimelineViewModel
    private let makeModel: @MainActor (SavedFilter) -> TimelineViewModel

    init(filter: SavedFilter, makeModel: @escaping @MainActor (SavedFilter) -> TimelineViewModel) {
        self.id = filter.id
        self.title = filter.name
        self.filter = filter
        self.makeModel = makeModel
        self.model = makeModel(filter)
    }

    /// A stable key over the expanded query content, so the view reloads only when
    /// the actual search changes (not on a pure rename).
    public var contentKey: String {
        filter.subqueries.joined(separator: "\u{1}") + "|" + filter.combinator.rawValue
    }

    /// One-line summary for the sidebar meta row.
    public var summary: String { filter.summary }

    /// Apply an edited filter: relabel, and if the expanded queries changed rebuild
    /// the model so the next appearance loads the new search.
    func apply(_ edited: SavedFilter) {
        let queriesChanged = edited.subqueries != filter.subqueries
        title = edited.name
        filter = edited
        if queriesChanged {
            model.stopPolling()
            model = makeModel(edited)
        }
    }
}

/// Holds the sidebar's tab state: the pinned home/notifications tabs, the saved
/// filter tabs (persisted via `SavedFilterStore`), and an ordered list of
/// conversation tabs (persisted via `ConversationPersisting`). Opening a post's
/// parent appends a conversation; closing a tab falls back to a neighbor of the
/// same kind, otherwise home.
@MainActor
public final class WorkspaceModel: ObservableObject {
    @Published public private(set) var filters: [FilterTab] = []
    @Published public private(set) var conversations: [ConversationTab] = [] {
        didSet { if !isRestoring { persist() } }
    }
    @Published public private(set) var authors: [AuthorTab] = []
    @Published public var selection: WorkspaceTab = .home {
        didSet { if !isRestoring { persist() } }
    }

    public let filterStore: SavedFilterStore
    private let makeThreadModel: @MainActor (String) -> ThreadViewModel
    private let makeFilterModel: @MainActor (SavedFilter) -> TimelineViewModel
    private let makeAuthorModel: @MainActor (String) -> TimelineViewModel
    private let makeAuthorHeader: @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel
    private let persistence: ConversationPersisting
    /// Set while `restore()` repopulates state from disk so the property observers
    /// do not write the just-loaded state straight back out.
    private var isRestoring = false

    public init(
        filterStore: SavedFilterStore,
        persistence: ConversationPersisting = EphemeralConversationStore(),
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeFilterModel: @escaping @MainActor (SavedFilter) -> TimelineViewModel,
        makeAuthorModel: @escaping @MainActor (String) -> TimelineViewModel,
        makeAuthorHeader: @escaping @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel
    ) {
        self.filterStore = filterStore
        self.persistence = persistence
        self.makeThreadModel = makeThreadModel
        self.makeFilterModel = makeFilterModel
        self.makeAuthorModel = makeAuthorModel
        self.makeAuthorHeader = makeAuthorHeader
        self.filters = filterStore.filters.map { FilterTab(filter: $0, makeModel: makeFilterModel) }
        restore()
    }

    /// Repopulate the open conversation tabs and selection from the persisted
    /// state, rebuilding each tab's `ThreadViewModel` so its thread reloads when
    /// first viewed.
    private func restore() {
        isRestoring = true
        defer { isRestoring = false }
        let state = persistence.load()
        conversations = state.conversations.map { saved in
            ConversationTab(saved: saved, model: makeThreadModel(saved.anchorID))
        }
        if let anchor = state.selectedAnchorID,
           let tab = conversations.first(where: { $0.anchorID == anchor }) {
            selection = .conversation(tab.id)
        } else {
            selection = .home
        }
    }

    /// Write the current open conversation tabs and selected anchor to the store.
    private func persist() {
        let selectedAnchorID: String? = {
            guard case let .conversation(id) = selection else { return nil }
            return conversations.first { $0.id == id }?.anchorID
        }()
        persistence.save(
            ConversationState(conversations: conversations.map(\.saved), selectedAnchorID: selectedAnchorID)
        )
    }

    // MARK: - Filters

    /// Create a filter from typed terms, append its tab, and select it. No-op when
    /// the terms expand to no usable query (the store rejects it).
    public func addFilter(name: String, terms: [FilterTerm], combinator: FilterCombinator) {
        guard let saved = filterStore.add(name: name, terms: terms, combinator: combinator) else { return }
        let tab = FilterTab(filter: saved, makeModel: makeFilterModel)
        filters.append(tab)
        selection = .filter(tab.id)
    }

    /// Persist an edited filter and reflect it in its tab (relabel / model swap).
    public func updateFilter(_ edited: SavedFilter) {
        filterStore.update(edited)
        guard let tab = filters.first(where: { $0.id == edited.id }) else { return }
        tab.apply(edited)
        filters = filters  // republish so the sidebar picks up the relabel
    }

    /// Delete a filter tab. When the closed tab was selected, select the adjacent
    /// filter if any, otherwise fall back to home.
    public func removeFilter(id: UUID) {
        let wasSelected = selection == .filter(id)
        let index = filters.firstIndex { $0.id == id }
        filterStore.remove(id: id)
        filters.first { $0.id == id }?.model.stopPolling()
        filters.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !filters.isEmpty {
            selection = .filter(filters[min(index, filters.count - 1)].id)
        } else {
            selection = .home
        }
    }

    /// Open (or re-select) a filter tab for a single hashtag, used when the viewer
    /// taps a hashtag in a post body. A leading `#` is stripped; a blank tag is a
    /// no-op. If a filter tab is already exactly this one hashtag it is re-selected
    /// rather than duplicated.
    public func openHashtagFilter(tag: String) {
        let clean = (tag.hasPrefix("#") ? String(tag.dropFirst()) : tag)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let existing = filters.first(where: { tab in
            tab.filter.terms.count == 1
                && tab.filter.terms[0].kind == .hashtag
                && tab.filter.terms[0].fragment == "#" + clean
        }) {
            selection = .filter(existing.id)
            return
        }
        addFilter(name: "#\(clean)", terms: [FilterTerm(kind: .hashtag, value: clean)], combinator: .and)
    }

    public func filter(id: UUID) -> FilterTab? { filters.first { $0.id == id } }

    /// The backing `SavedFilter` for an id (for the editor); nil if absent.
    public func savedFilter(id: UUID) -> SavedFilter? { filterStore.filters.first { $0.id == id } }

    // MARK: - Conversations

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

    // MARK: - Authors

    /// Open `did` in a view-only author tab. If a tab for the same user already
    /// exists it is re-selected rather than duplicated. The tapped avatar's basics
    /// seed an instant header while the full profile loads.
    public func openAuthor(did: String, handle: String, displayName: String, avatarURL: URL?) {
        if let existing = authors.first(where: { $0.did == did }) {
            selection = .author(existing.id)
            return
        }
        let initial = AuthorProfile(
            did: did, handle: handle,
            displayName: displayName.isEmpty ? nil : displayName,
            avatarURL: avatarURL, bio: nil
        )
        let tab = AuthorTab(
            did: did, handle: handle, displayName: displayName, avatarURL: avatarURL,
            model: makeAuthorModel(did),
            header: makeAuthorHeader(did, initial)
        )
        authors.append(tab)
        selection = .author(tab.id)
    }

    /// Close an author tab. When the closed tab was selected, select the adjacent
    /// author if any, otherwise fall back to home.
    public func closeAuthor(_ id: UUID) {
        let wasSelected = selection == .author(id)
        let index = authors.firstIndex { $0.id == id }
        authors.first { $0.id == id }?.model.stopPolling()
        authors.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !authors.isEmpty {
            selection = .author(authors[min(index, authors.count - 1)].id)
        } else {
            selection = .home
        }
    }

    public func author(id: UUID) -> AuthorTab? {
        authors.first { $0.id == id }
    }

    // MARK: - Cycling

    /// All tabs in display order: the two pinned tabs, the filters, then the open
    /// conversations. Drives the Cmd-Shift-J/K cycling shortcuts.
    public var orderedTabs: [WorkspaceTab] {
        [.home, .notifications]
            + filters.map { .filter($0.id) }
            + conversations.map { .conversation($0.id) }
            + authors.map { .author($0.id) }
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
