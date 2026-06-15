import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ThreadViewModelTests: XCTestCase {
    private final class StubLoader: ThreadLoading, @unchecked Sendable {
        var result: Result<ConversationThread, Error>
        private(set) var requestedURIs: [String] = []
        init(result: Result<ConversationThread, Error>) { self.result = result }
        func loadThread(uri: String) async throws -> ConversationThread {
            requestedURIs.append(uri)
            return try result.get()
        }
    }

    private struct StubError: Error {}

    private final class FakeInteractor: PostInteracting, @unchecked Sendable {
        func like(uri: String, cid: String) async throws -> String { "at://me/app.bsky.feed.like/new" }
        func removeLike(recordURI: String) async throws {}
        func repost(uri: String, cid: String) async throws -> String { "at://me/app.bsky.feed.repost/new" }
        func removeRepost(recordURI: String) async throws {}
        func deletePost(uri: String) async throws {}
    }

    func testToggleLikeUpdatesFocusedPost() async {
        let focus = sample(id: "reply")
        let thread = ConversationThread(focus: focus, replies: [])
        let vm = ThreadViewModel(loader: StubLoader(result: .success(thread)), uri: "reply", interactor: FakeInteractor())
        await vm.load()

        await vm.toggleLike(focus)

        guard case let .loaded(updated) = vm.state else { return XCTFail("expected loaded") }
        XCTAssertTrue(updated.focus.isLiked)
        XCTAssertEqual(updated.focus.viewerLikeURI, "at://me/app.bsky.feed.like/new")
    }

    private func sample(id: String, parent: PostDisplay? = nil) -> PostDisplay {
        PostDisplay(
            id: id, authorDisplayName: "Bob", authorHandle: "bob.bsky.social",
            body: "reply", createdAt: Date(timeIntervalSince1970: 1_780_574_400),
            replyParent: parent.map(ReplyParent.init)
        )
    }

    func testToggleLikePreservesReplies() async {
        let focus = sample(id: "reply")
        let child = ThreadNode(post: sample(id: "child"), replies: [], depth: 0)
        let thread = ConversationThread(focus: focus, replies: [child])
        let vm = ThreadViewModel(loader: StubLoader(result: .success(thread)), uri: "reply", interactor: FakeInteractor())
        await vm.load()

        await vm.toggleLike(focus)

        guard case let .loaded(updated) = vm.state else { return XCTFail("expected loaded") }
        XCTAssertEqual(updated.replies.count, 1, "the child reply tree must survive a focus like")
        XCTAssertEqual(updated.replies.first?.id, "child")
    }

    func testInitialStateIsIdle() {
        let thread = ConversationThread(focus: sample(id: "x"), replies: [])
        let vm = ThreadViewModel(loader: StubLoader(result: .success(thread)), uri: "x")
        XCTAssertEqual(vm.state, .idle)
    }

    func testSuccessfulLoadReachesLoadedAndRequestsURI() async {
        let parent = sample(id: "root")
        let focus = sample(id: "reply", parent: parent)
        let thread = ConversationThread(focus: focus, replies: [])
        let loader = StubLoader(result: .success(thread))
        let vm = ThreadViewModel(loader: loader, uri: "reply")

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(thread))
        XCTAssertEqual(loader.requestedURIs, ["reply"])
    }

    func testFailedLoadReachesFailed() async {
        let vm = ThreadViewModel(loader: StubLoader(result: .failure(StubError())), uri: "x")
        await vm.load()
        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
    }
}
