import XCTest
@testable import YoruMimizukuKit

// Test methods are `async` (despite having no awaits): swift-corelibs-xctest on
// Windows routes `@MainActor` test methods through its async invoker, which
// handles the MainActor isolation correctly. A `@MainActor` class whose methods
// are all synchronous falls into the sync invoker and crashes with a function
// cast failure, aborting the whole run. `async` keeps this suite runnable on
// Windows and is a no-op on macOS.
@MainActor
final class WorkspaceModelTests: XCTestCase {
    private final class StubThreadLoader: ThreadLoading, @unchecked Sendable {
        func loadThread(uri: String) async throws -> ConversationThread {
            let post = PostDisplay(id: uri, authorDisplayName: "x", authorHandle: "x", body: "x", createdAt: Date())
            return ConversationThread(focus: post, replies: [])
        }
    }

    private final class StubTimelineLoader: TimelineLoading, @unchecked Sendable {
        func loadPage(cursor: String?) async throws -> TimelinePage { TimelinePage(posts: [], cursor: nil) }
    }

    private final class InMemoryFilterPort: SavedFilterStoring, @unchecked Sendable {
        func load() throws -> [SavedFilter] { [] }
        func save(_ filters: [SavedFilter]) throws {}
    }

    private final class FakePersistence: ConversationPersisting, @unchecked Sendable {
        var state: ConversationState
        private(set) var saveCount = 0
        init(state: ConversationState = ConversationState()) { self.state = state }
        func load() -> ConversationState { state }
        func save(_ state: ConversationState) { self.state = state; saveCount += 1 }
    }

    private final class StubAuthorProfileLoader: AuthorProfileLoading, @unchecked Sendable {
        func loadProfile(actor: String) async throws -> AuthorProfile {
            AuthorProfile(did: actor, handle: "x", displayName: "x", avatarURL: nil, bio: nil)
        }
    }

    private func makeModel(persistence: ConversationPersisting) -> WorkspaceModel {
        WorkspaceModel(
            filterStore: SavedFilterStore(port: InMemoryFilterPort()),
            persistence: persistence,
            makeThreadModel: { uri in ThreadViewModel(loader: StubThreadLoader(), uri: uri) },
            makeFilterModel: { _ in TimelineViewModel(loader: StubTimelineLoader()) },
            makeAuthorModel: { _ in TimelineViewModel(loader: StubTimelineLoader()) },
            makeAuthorHeader: { did, initial in
                ProfileHeaderViewModel(loader: StubAuthorProfileLoader(), actor: did, initial: initial)
            }
        )
    }

    private func post(id: String, name: String = "Alice", handle: String = "alice.bsky.social") -> PostDisplay {
        PostDisplay(id: id, authorDisplayName: name, authorHandle: handle, body: "body", createdAt: Date())
    }

    func testRestoresSavedConversationsOnInit() async {
        let persistence = FakePersistence(state: ConversationState(
            conversations: [
                SavedConversation(anchorID: "at://a", title: "Alice", handle: "@alice", subtitle: "hi"),
                SavedConversation(anchorID: "at://b", title: "Bob", handle: "@bob", subtitle: "yo")
            ],
            selectedAnchorID: "at://b"
        ))

        let model = makeModel(persistence: persistence)

        XCTAssertEqual(model.conversations.map(\.anchorID), ["at://a", "at://b"])
        XCTAssertEqual(model.conversations.map(\.title), ["Alice", "Bob"])
        guard case let .conversation(id) = model.selection else { return XCTFail("expected conversation selection") }
        XCTAssertEqual(model.conversation(id: id)?.anchorID, "at://b")
    }

    func testRestoreWithNoSelectionFallsBackToHome() async {
        let persistence = FakePersistence(state: ConversationState(
            conversations: [SavedConversation(anchorID: "at://a", title: "Alice", handle: "@alice", subtitle: "hi")],
            selectedAnchorID: nil
        ))

        let model = makeModel(persistence: persistence)

        XCTAssertEqual(model.selection, .home)
    }

    func testOpenConversationPersistsTabAndSelection() async {
        let persistence = FakePersistence()
        let model = makeModel(persistence: persistence)

        model.openConversation(post(id: "at://a"))

        XCTAssertEqual(persistence.state.conversations.map(\.anchorID), ["at://a"])
        XCTAssertEqual(persistence.state.selectedAnchorID, "at://a")
    }

    func testOpenConversationByURIReusesExistingTab() async {
        let persistence = FakePersistence()
        let model = makeModel(persistence: persistence)

        model.openConversation(anchorID: "at://a", title: "Alice", handle: "@alice", subtitle: "liked post")
        let firstID = model.conversations[0].id
        model.selection = .home
        model.openConversation(anchorID: "at://a", title: "Alice changed", handle: "@alice", subtitle: "changed")

        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertEqual(model.conversations[0].title, "Alice")
        XCTAssertEqual(model.selection, .conversation(firstID))
        XCTAssertEqual(persistence.state.conversations.map(\.anchorID), ["at://a"])
    }

    func testCloseConversationPersistsRemoval() async {
        let persistence = FakePersistence()
        let model = makeModel(persistence: persistence)
        model.openConversation(post(id: "at://a"))
        let id = model.conversations[0].id

        model.closeConversation(id)

        XCTAssertTrue(persistence.state.conversations.isEmpty)
        XCTAssertNil(persistence.state.selectedAnchorID)
    }

    func testOpenHashtagFilterCreatesAndSelectsFilterTab() async {
        let model = makeModel(persistence: FakePersistence())

        model.openHashtagFilter(tag: "swift")

        XCTAssertEqual(model.filters.count, 1)
        let tab = model.filters[0]
        XCTAssertEqual(tab.filter.terms.map(\.kind), [.hashtag])
        XCTAssertEqual(tab.filter.terms.first?.value, "swift")
        XCTAssertEqual(model.selection, .filter(tab.id))
    }

    func testOpenHashtagFilterStripsLeadingHash() async {
        let model = makeModel(persistence: FakePersistence())

        model.openHashtagFilter(tag: "#swift")

        XCTAssertEqual(model.filters.first?.filter.terms.first?.value, "swift")
    }

    func testOpenHashtagFilterReusesExistingTab() async {
        let model = makeModel(persistence: FakePersistence())
        model.openHashtagFilter(tag: "swift")
        let firstID = model.filters[0].id
        model.selection = .home

        model.openHashtagFilter(tag: "swift")

        XCTAssertEqual(model.filters.count, 1)
        XCTAssertEqual(model.selection, .filter(firstID))
    }

    func testOpenHashtagFilterIgnoresBlankTag() async {
        let model = makeModel(persistence: FakePersistence())

        model.openHashtagFilter(tag: "#")

        XCTAssertTrue(model.filters.isEmpty)
        XCTAssertEqual(model.selection, .home)
    }

    func testEditingFilterQueryStopsOldModelPolling() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "Swift", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)
        let tab = model.filters[0]
        let oldModel = tab.model
        oldModel.startPolling(every: .seconds(30))
        XCTAssertTrue(oldModel.isPolling)

        guard let saved = model.savedFilter(id: tab.id) else { return XCTFail("expected saved filter") }
        let edited = SavedFilter(
            id: saved.id,
            name: saved.name,
            terms: [FilterTerm(kind: .keyword, value: "rust")],
            combinator: saved.combinator,
            createdAt: saved.createdAt
        )
        model.updateFilter(edited)

        XCTAssertFalse(tab.model === oldModel)
        XCTAssertFalse(oldModel.isPolling)
    }

    func testOpenAuthorAppendsAndSelects() async {
        let model = makeModel(persistence: FakePersistence())

        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)

        XCTAssertEqual(model.authors.map(\.did), ["did:plc:alice"])
        XCTAssertEqual(model.authors[0].handle, "alice.bsky.social")
        XCTAssertEqual(model.authors[0].displayName, "Alice")
        guard case let .author(id) = model.selection else { return XCTFail("expected author selection") }
        XCTAssertEqual(model.author(id: id)?.did, "did:plc:alice")
    }

    func testOpenAuthorDedupesByDID() async {
        let model = makeModel(persistence: FakePersistence())

        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)
        let firstID = model.authors[0].id
        model.selection = .home
        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice (changed)", avatarURL: nil)

        XCTAssertEqual(model.authors.count, 1)
        XCTAssertEqual(model.selection, .author(firstID))
    }

    func testCloseAuthorSelectsAdjacentThenHome() async {
        let model = makeModel(persistence: FakePersistence())
        model.openAuthor(did: "did:plc:a", handle: "a", displayName: "A", avatarURL: nil)
        model.openAuthor(did: "did:plc:b", handle: "b", displayName: "B", avatarURL: nil)
        let bID = model.authors[1].id

        model.closeAuthor(bID)
        XCTAssertEqual(model.authors.map(\.did), ["did:plc:a"])
        XCTAssertEqual(model.selection, .author(model.authors[0].id))

        model.closeAuthor(model.authors[0].id)
        XCTAssertTrue(model.authors.isEmpty)
        XCTAssertEqual(model.selection, .home)
    }

    func testOrderedTabsAppendsAuthorsLast() async {
        let model = makeModel(persistence: FakePersistence())
        model.openConversation(post(id: "at://c"))
        model.openAuthor(did: "did:plc:a", handle: "a", displayName: "A", avatarURL: nil)

        XCTAssertEqual(model.orderedTabs.last, .author(model.authors[0].id))
    }

    func testRestoreThenReopenRoundTrips() async {
        // Simulate a relaunch: persist with one model, restore with a fresh one
        // backed by the same store.
        let persistence = FakePersistence()
        let first = makeModel(persistence: persistence)
        first.openConversation(post(id: "at://a", name: "Alice"))

        let restored = makeModel(persistence: persistence)

        XCTAssertEqual(restored.conversations.map(\.anchorID), ["at://a"])
        XCTAssertEqual(restored.conversations.first?.title, "Alice")
    }

    func testSelectionTitleForHome() async {
        let model = makeModel(persistence: FakePersistence())
        XCTAssertEqual(model.selectionTitle, "ホーム")
    }

    func testSelectionTitleForNotifications() async {
        let model = makeModel(persistence: FakePersistence())
        model.selection = .notifications
        XCTAssertEqual(model.selectionTitle, "通知")
    }

    func testSelectionTitleForFilterTab() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "Swift", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)
        XCTAssertEqual(model.selectionTitle, "Swift")
    }

    func testSelectionTitleForConversationTab() async {
        let model = makeModel(persistence: FakePersistence())
        model.openConversation(post(id: "at://a", name: "Alice"))
        XCTAssertEqual(model.selectionTitle, "Alice")
    }

    func testSelectionTitleForAuthorTabUsesDisplayNameThenHandle() async {
        let model = makeModel(persistence: FakePersistence())
        model.openAuthor(did: "did:plc:a", handle: "a.bsky.social", displayName: "Alice", avatarURL: nil)
        XCTAssertEqual(model.selectionTitle, "Alice")

        model.openAuthor(did: "did:plc:b", handle: "b.bsky.social", displayName: "", avatarURL: nil)
        XCTAssertEqual(model.selectionTitle, "b.bsky.social")
    }

    func testSelectionTitleFallsBackToHomeWhenTabClosed() async {
        let model = makeModel(persistence: FakePersistence())
        model.openConversation(post(id: "at://a", name: "Alice"))
        guard case let .conversation(id) = model.selection else { return XCTFail("expected conversation selection") }
        model.closeConversation(id)
        // closeConversation already re-selects, so force the stale-id case directly.
        model.selection = .conversation(id)
        XCTAssertEqual(model.selectionTitle, "ホーム")
    }

    // MARK: - Saved feeds (macOS sidebar)

    private func savedSource(_ id: String, _ title: String, _ kind: SavedFeedSource.Kind = .feed) -> SavedFeedSource {
        SavedFeedSource(id: id, kind: kind, title: title, description: nil, creatorHandle: nil, avatarURL: nil)
    }

    /// The sidebar groups pinned feeds before pinned lists, so cycling follows
    /// that grouping rather than the raw pin order.
    func testOrderedTabsPutSavedFeedsThenListsBetweenNotificationsAndFilters() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "f", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)
        model.savedFeeds = [savedSource("at://f/a", "A"), savedSource("at://l/l", "L", .list), savedSource("at://f/b", "B")]

        XCTAssertEqual(
            Array(model.orderedTabs.prefix(5)),
            [.home, .notifications, .savedFeed("at://f/a"), .savedFeed("at://f/b"), .savedFeed("at://l/l")]
        )
        guard case .filter = model.orderedTabs[5] else { return XCTFail("filters follow the saved feeds") }
    }

    func testSelectionTitleForSavedFeedIsItsTitle() async {
        let model = makeModel(persistence: FakePersistence())
        model.savedFeeds = [savedSource("at://f/a", "話題の議論")]
        model.selection = .savedFeed("at://f/a")

        XCTAssertEqual(model.selectionTitle, "話題の議論")
    }

    func testUnpinningTheSelectedSavedFeedFallsBackToHome() async {
        let model = makeModel(persistence: FakePersistence())
        model.savedFeeds = [savedSource("at://f/a", "A")]
        model.selection = .savedFeed("at://f/a")

        model.savedFeeds = []

        XCTAssertEqual(model.selection, .home)
    }

    // MARK: - Dropping a person on a filter

    private func userTerms(_ model: WorkspaceModel, _ id: UUID) -> [String] {
        model.savedFilter(id: id)?.terms.filter { $0.kind == .user }.map(\.value) ?? []
    }

    func testDroppingAPersonOnAFilterAddsAFromTerm() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "Swift", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)
        let id = model.filters[0].id

        XCTAssertEqual(model.addAuthor(handle: "@alice.example", toFilter: id), .added)
        XCTAssertEqual(userTerms(model, id), ["alice.example"])
        XCTAssertEqual(model.savedFilter(id: id)?.terms.first?.value, "swift")
    }

    func testDroppingSomeoneAlreadyInTheFilterChangesNothing() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "people", terms: [FilterTerm(kind: .user, value: "alice.example")], combinator: .or)
        let id = model.filters[0].id

        XCTAssertEqual(model.addAuthor(handle: "Alice.example", toFilter: id), .alreadyIncluded)
        XCTAssertEqual(userTerms(model, id), ["alice.example"])
    }

    /// In an AND filter two from: terms can never both match, so the drop is refused.
    func testDroppingASecondPersonOnAnAndFilterIsRefused() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "alice", terms: [FilterTerm(kind: .user, value: "alice.example")], combinator: .and)
        let id = model.filters[0].id

        XCTAssertEqual(model.addAuthor(handle: "bob.example", toFilter: id), .wouldMatchNothing)
        XCTAssertEqual(userTerms(model, id), ["alice.example"])
    }

    /// A filter saved from a toolbar search keeps `from:` inside a keyword term;
    /// it names a person just the same.
    func testAFromInsideAKeywordCountsAsAPersonInAnAndFilter() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "alice", terms: [FilterTerm(kind: .keyword, value: "swift from:alice.example")], combinator: .and)
        let id = model.filters[0].id

        XCTAssertEqual(model.addAuthor(handle: "bob.example", toFilter: id), .wouldMatchNothing)
    }

    func testDroppingASecondPersonOnAnOrFilterAddsThem() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "people", terms: [FilterTerm(kind: .user, value: "alice.example")], combinator: .or)
        let id = model.filters[0].id

        XCTAssertEqual(model.addAuthor(handle: "bob.example", toFilter: id), .added)
        XCTAssertEqual(userTerms(model, id), ["alice.example", "bob.example"])
    }

    // MARK: - ⌘1…⌘9

    func testShortcutTabsFollowTheSidebarOrderUpToNine() async {
        let model = makeModel(persistence: FakePersistence())
        model.savedFeeds = (1...6).map { savedSource("at://f/\($0)", "F\($0)") } + [savedSource("at://l/1", "L1", .list)]
        model.addFilter(name: "Swift", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)

        let tabs = model.shortcutTabs

        XCTAssertEqual(tabs.count, 9)
        XCTAssertEqual(tabs.map { model.title(for: $0) }, ["ホーム", "通知", "F1", "F2", "F3", "F4", "F5", "F6", "L1"])
    }

    func testTitleForAFilterIsItsName() async {
        let model = makeModel(persistence: FakePersistence())
        model.addFilter(name: "Swift", terms: [FilterTerm(kind: .keyword, value: "swift")], combinator: .and)

        XCTAssertEqual(model.title(for: .filter(model.filters[0].id)), "Swift")
    }

    // MARK: - Transient search (macOS toolbar)

    func testOpeningASearchShowsItWithoutAddingAFilter() async {
        let model = makeModel(persistence: FakePersistence())

        model.openSearch(query: "  swift concurrency ")

        XCTAssertEqual(model.selection, .search)
        XCTAssertEqual(model.search?.query, "swift concurrency")
        XCTAssertEqual(model.selectionTitle, "検索: swift concurrency")
        XCTAssertTrue(model.filters.isEmpty)
        XCTAssertFalse(model.orderedTabs.contains(.search))
    }

    func testABlankSearchDoesNothing() async {
        let model = makeModel(persistence: FakePersistence())

        model.openSearch(query: "   ")

        XCTAssertEqual(model.selection, .home)
        XCTAssertNil(model.search)
    }

    func testLeavingASearchDiscardsItAndStopsItsPolling() async throws {
        let model = makeModel(persistence: FakePersistence())
        model.openSearch(query: "swift")
        let timeline = try XCTUnwrap(model.search?.model)
        timeline.startPolling(every: .seconds(3600))

        model.selection = .notifications

        XCTAssertNil(model.search)
        XCTAssertFalse(timeline.isPolling)
    }

    func testSavingASearchTurnsItIntoASelectedFilter() async {
        let model = makeModel(persistence: FakePersistence())
        model.openSearch(query: "swift")

        model.saveSearchAsFilter()

        XCTAssertNil(model.search)
        XCTAssertEqual(model.filters.map(\.title), ["swift"])
        XCTAssertEqual(model.selection, .filter(model.filters[0].id))
        XCTAssertEqual(model.savedFilter(id: model.filters[0].id)?.terms.map(\.value), ["swift"])
    }
}
