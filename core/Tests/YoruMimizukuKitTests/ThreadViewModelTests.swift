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

    private final class FailingInteractor: PostInteracting, @unchecked Sendable {
        func like(uri: String, cid: String) async throws -> String { throw StubError() }
        func removeLike(recordURI: String) async throws { throw StubError() }
        func repost(uri: String, cid: String) async throws -> String { throw StubError() }
        func removeRepost(recordURI: String) async throws { throw StubError() }
        func deletePost(uri: String) async throws { throw StubError() }
    }

    private final class FakeInteractor: PostInteracting, @unchecked Sendable {
        func like(uri: String, cid: String) async throws -> String { "at://me/app.bsky.feed.like/new" }
        func removeLike(recordURI: String) async throws {}
        func repost(uri: String, cid: String) async throws -> String { "at://me/app.bsky.feed.repost/new" }
        func removeRepost(recordURI: String) async throws {}
        func deletePost(uri: String) async throws {}
    }

    // Leaving a page in the detail pane cancels its view's load task; coming back
    // must load again instead of showing an error screen.
    func testCancelledLoadReturnsToIdleSoItLoadsAgain() async {
        let vm = ThreadViewModel(loader: StubLoader(result: .failure(CancellationError())), uri: "at://a/1")

        await vm.load()

        guard case .idle = vm.state else { return XCTFail("expected idle, got \(vm.state)") }
    }

    /// Holds the first request open until the test releases it; later requests
    /// succeed at once.
    private final class FirstCallGatedLoader: ThreadLoading, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var held: CheckedContinuation<ConversationThread, Error>?
        let thread: ConversationThread
        init(thread: ConversationThread) { self.thread = thread }

        var isHolding: Bool { lock.withLock { held != nil } }

        func loadThread(uri: String) async throws -> ConversationThread {
            let isFirst = lock.withLock { calls += 1; return calls == 1 }
            guard isFirst else { return thread }
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock { held = continuation }
            }
        }

        func releaseFirst(with error: Error) {
            let continuation = lock.withLock { () -> CheckedContinuation<ConversationThread, Error>? in
                defer { held = nil }
                return held
            }
            continuation?.resume(throwing: error)
        }
    }

    // Going back to a conversation whose first load is still being cancelled
    // starts a new load; the old load's late cancellation must not reset it.
    func testLateCancellationOfAnEarlierLoadDoesNotResetANewerOne() async throws {
        let thread = ConversationThread(focus: sample(id: "at://a/1"), replies: [])
        let loader = FirstCallGatedLoader(thread: thread)
        let vm = ThreadViewModel(loader: loader, uri: "at://a/1")
        let first = Task { await vm.load() }
        for _ in 0..<200 where !loader.isHolding { try await Task.sleep(for: .milliseconds(5)) }
        guard loader.isHolding else { return XCTFail("the first load never reached the loader") }

        await vm.load()
        loader.releaseFirst(with: CancellationError())
        await first.value

        guard case .loaded = vm.state else { return XCTFail("expected loaded, got \(vm.state)") }
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

    // j/k shows a timeline post in the detail pane at once; only the replies wait
    // for the thread.
    func testPreviewIsShownUntilTheThreadArrives() async throws {
        let preview = sample(id: "reply")
        let loaded = ConversationThread(focus: sample(id: "reply"), replies: [ThreadNode(post: sample(id: "child"), replies: [], depth: 0)])
        let loader = FirstCallGatedLoader(thread: loaded)
        let vm = ThreadViewModel(loader: loader, uri: "reply", preview: preview)
        XCTAssertEqual(vm.focus, preview)

        let first = Task { await vm.load() }
        while !loader.isHolding { await Task.yield() }
        XCTAssertEqual(vm.focus, preview, "the preview stays while the thread loads")

        loader.releaseFirst(with: StubError())
        await first.value
        XCTAssertEqual(vm.focus, preview, "a failed thread load keeps the post on screen")

        await vm.load()
        XCTAssertEqual(vm.state, .loaded(loaded))
        XCTAssertEqual(vm.focus, loaded.focus)
    }



    // The preview is a timeline row's copy, possibly from before the viewer's
    // latest like or from another account's fetch, so it is for reading only:
    // likes and reposts act on the thread once it arrives.
    func testLikesWaitForTheThread() async {
        let preview = sample(id: "reply")
        let vm = ThreadViewModel(
            loader: StubLoader(result: .failure(StubError())), uri: "reply",
            interactor: FakeInteractor(), preview: preview
        )

        await vm.toggleLike(preview)

        XCTAssertEqual(vm.focus, preview)
    }

    // Undoing a failed like puts back the loaded post.
    func testAFailedLikeKeepsTheLoadedAncestors() async {
        let focus = sample(id: "reply", parent: sample(id: "root"))
        let thread = ConversationThread(focus: focus, replies: [])
        let vm = ThreadViewModel(
            loader: StubLoader(result: .success(thread)), uri: "reply",
            interactor: FailingInteractor(), preview: sample(id: "reply")
        )
        await vm.load()

        await vm.toggleLike(focus)

        XCTAssertEqual(vm.focus?.isLiked, false)
        XCTAssertEqual(vm.focus?.replyParent?.post.id, "root")
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
