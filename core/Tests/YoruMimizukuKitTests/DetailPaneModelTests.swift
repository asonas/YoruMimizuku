import XCTest
@testable import YoruMimizukuKit

// Test methods are `async` so swift-corelibs-xctest on Windows runs these
// `@MainActor` tests through its async invoker (see WorkspaceModelTests).
@MainActor
final class DetailPaneModelTests: XCTestCase {
    private final class StubThreadLoader: ThreadLoading, @unchecked Sendable {
        func loadThread(uri: String) async throws -> ConversationThread {
            let post = PostDisplay(id: uri, authorDisplayName: "x", authorHandle: "x", body: "x", createdAt: Date())
            return ConversationThread(focus: post, replies: [])
        }
    }

    private final class StubTimelineLoader: TimelineLoading, @unchecked Sendable {
        func loadPage(cursor: String?) async throws -> TimelinePage { TimelinePage(posts: [], cursor: nil) }
    }

    private final class StubAuthorProfileLoader: AuthorProfileLoading, @unchecked Sendable {
        func loadProfile(actor: String) async throws -> AuthorProfile {
            AuthorProfile(did: actor, handle: "x", displayName: "x", avatarURL: nil, bio: nil)
        }
    }

    private func makePane() -> DetailPaneModel {
        DetailPaneModel(
            makeThreadModel: { uri, preview in ThreadViewModel(loader: StubThreadLoader(), uri: uri, preview: preview) },
            makeAuthorModel: { _ in TimelineViewModel(loader: StubTimelineLoader()) },
            makeAuthorHeader: { did, initial in
                ProfileHeaderViewModel(loader: StubAuthorProfileLoader(), actor: did, initial: initial)
            }
        )
    }

    private func post(_ id: String) -> PostDisplay {
        PostDisplay(id: id, authorDisplayName: "Alice", authorHandle: "alice.bsky.social", body: "body", createdAt: Date())
    }

    private func anchorID(of entry: DetailEntry?) -> String? {
        if case let .conversation(tab) = entry { return tab.anchorID }
        return nil
    }

    /// A post opened from a row is on screen before its thread loads.
    func testOpeningAPostShowsItBeforeTheThreadLoads() async {
        let pane = makePane()
        let opened = post("at://a/1")
        pane.openConversation(opened)

        guard case let .conversation(tab) = pane.current else { return XCTFail("expected a conversation") }
        XCTAssertEqual(tab.model.focus, opened)
    }

    /// A conversation opened from a notification has no post to show until its
    /// thread loads; choosing the same post in a timeline supplies it.
    func testChoosingTheShownConversationFromARowSuppliesItsPost() async {
        let pane = makePane()
        pane.openConversation(anchorID: "at://a/1", title: "Alice", handle: "alice.bsky.social", subtitle: "")
        let shown = pane.currentID
        let row = post("at://a/1")
        pane.openConversation(row)

        guard case let .conversation(tab) = pane.current else { return XCTFail("expected a conversation") }
        XCTAssertEqual(pane.currentID, shown, "the page and its load are kept")
        XCTAssertEqual(tab.model.focus, row)
    }

    func testShowingTheRecordOfTheShownConversationSuppliesItsPost() async {
        let pane = makePane()
        pane.openConversation(anchorID: "at://a/1", title: "Alice", handle: "alice.bsky.social", subtitle: "")
        let row = post("at://a/1")
        pane.openRecord(row)

        guard case let .conversation(tab) = pane.current else { return XCTFail("expected a conversation") }
        XCTAssertEqual(pane.tab, .record)
        XCTAssertEqual(tab.model.focus, row)
    }

    /// Reopening the shown conversation keeps its loaded page rather than
    /// rebuilding it.
    func testOpeningTheShownConversationAgainKeepsThePage() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))
        let shown = pane.currentID
        pane.openConversation(post("at://a/1"))

        XCTAssertEqual(pane.currentID, shown)
    }

    /// One page at a time, as in the desktop prototype: opening another
    /// replaces it, with no history to go back to.
    func testOpeningAnotherPageReplacesTheShownOne() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))

        pane.openConversation(post("at://a/2"))

        XCTAssertEqual(anchorID(of: pane.current), "at://a/2")
    }

    func testLeavingAnAuthorPageStopsItsPolling() async {
        let pane = makePane()
        pane.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)
        guard case let .author(tab) = pane.current else { return XCTFail("author page is not shown") }
        tab.model.startPolling(every: .seconds(60))

        pane.openConversation(post("at://a/1"))

        XCTAssertFalse(tab.model.isPolling)
    }

    func testCloseEmptiesThePane() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))

        pane.close()

        XCTAssertNil(pane.current)
    }

    /// 投稿 > レコードを表示 opens the post on its レコード tab; any other page
    /// opens on its thread.
    func testOpeningARecordShowsTheRecordTabUntilAnotherPageOpens() async {
        let pane = makePane()

        pane.openRecord(post("at://a/1"))
        XCTAssertEqual(anchorID(of: pane.current), "at://a/1")
        XCTAssertEqual(pane.tab, .record)

        pane.openConversation(post("at://a/2"))
        XCTAssertEqual(pane.tab, .thread)

        // Opening the shown post again from the timeline means "show its thread".
        pane.openRecord(post("at://a/2"))
        pane.openConversation(post("at://a/2"))
        XCTAssertEqual(pane.tab, .thread)
    }

    /// The same holds when the post is opened by URI (a quote or notification).
    func testOpeningTheShownPostByURIReturnsToItsThread() async {
        let pane = makePane()
        pane.openConversation(anchorID: "at://a/1", title: "A", handle: "a", subtitle: "")
        pane.tab = .record

        pane.openConversation(anchorID: "at://a/1", title: "A", handle: "a", subtitle: "")

        XCTAssertEqual(pane.tab, .thread)
    }

    private func revealsMedia(_ pane: DetailPaneModel) -> Bool? {
        if case let .conversation(tab) = pane.current { return tab.model.revealsMedia }
        return nil
    }

    /// Revealing a post's media from the timeline shows that post with its media
    /// uncovered, even while another page is open.
    func testRevealingMediaOpensThePostWithItsMediaShown() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))

        pane.toggleMediaReveal(post("at://a/2"))

        XCTAssertEqual(anchorID(of: pane.current), "at://a/2")
        XCTAssertEqual(revealsMedia(pane), true)
    }

    func testRevealingTheShownPostsMediaAgainCoversIt() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))

        pane.toggleMediaReveal(post("at://a/1"))
        pane.toggleMediaReveal(post("at://a/1"))

        XCTAssertEqual(anchorID(of: pane.current), "at://a/1")
        XCTAssertEqual(revealsMedia(pane), false)
    }
}
