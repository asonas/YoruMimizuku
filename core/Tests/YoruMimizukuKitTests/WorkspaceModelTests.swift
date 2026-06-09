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
}
