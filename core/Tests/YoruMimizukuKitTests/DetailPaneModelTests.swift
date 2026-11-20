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
            makeThreadModel: { uri in ThreadViewModel(loader: StubThreadLoader(), uri: uri) },
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

    func testOpeningTheShownConversationAgainDoesNotGrowHistory() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))
        pane.openConversation(post("at://a/1"))

        XCTAssertEqual(anchorID(of: pane.current), "at://a/1")
        XCTAssertFalse(pane.canGoBack)
    }

    func testBackAndForwardMoveThroughOpenedPages() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))
        pane.openConversation(post("at://a/2"))

        pane.goBack()
        XCTAssertEqual(anchorID(of: pane.current), "at://a/1")
        XCTAssertTrue(pane.canGoForward)

        pane.goForward()
        XCTAssertEqual(anchorID(of: pane.current), "at://a/2")
        XCTAssertFalse(pane.canGoForward)
    }

    func testOpeningAfterGoingBackDropsTheForwardPages() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))
        pane.openConversation(post("at://a/2"))
        pane.goBack()

        pane.openConversation(post("at://a/3"))

        XCTAssertEqual(anchorID(of: pane.current), "at://a/3")
        XCTAssertFalse(pane.canGoForward)
        pane.goBack()
        XCTAssertEqual(anchorID(of: pane.current), "at://a/1")
    }

    func testLeavingAnAuthorPageStopsItsPolling() async {
        let pane = makePane()
        pane.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)
        pane.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)
        guard case let .author(tab) = pane.current else { return XCTFail("author page is not shown") }
        XCTAssertFalse(pane.canGoBack)
        tab.model.startPolling(every: .seconds(60))

        pane.openConversation(post("at://a/1"))

        XCTAssertFalse(tab.model.isPolling)
    }

    func testCloseEmptiesThePane() async {
        let pane = makePane()
        pane.openConversation(post("at://a/1"))
        pane.openConversation(post("at://a/2"))

        pane.close()

        XCTAssertNil(pane.current)
        XCTAssertFalse(pane.canGoBack)
        XCTAssertFalse(pane.canGoForward)
    }

    func testHistoryKeepsTheLatestThirtyPages() async {
        let pane = makePane()
        for n in 1...31 { pane.openConversation(post("at://a/\(n)")) }

        while pane.canGoBack { pane.goBack() }

        XCTAssertEqual(anchorID(of: pane.current), "at://a/2")
    }
}
