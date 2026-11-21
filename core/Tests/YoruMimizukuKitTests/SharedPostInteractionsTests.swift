import XCTest
@testable import YoruMimizukuKit

/// A window's timeline and its conversation pane show the same post: a like or
/// repost made in one shows in the other.
@MainActor
final class SharedPostInteractionsTests: XCTestCase {
    private struct StubError: Error {}

    private final class StubTimelineLoader: TimelineLoading, @unchecked Sendable {
        let posts: [PostDisplay]
        init(posts: [PostDisplay]) { self.posts = posts }
        func loadPage(cursor: String?) async throws -> TimelinePage { TimelinePage(posts: posts, cursor: nil) }
    }

    private final class StubThreadLoader: ThreadLoading, @unchecked Sendable {
        var focus: PostDisplay
        var fails = false
        init(focus: PostDisplay) { self.focus = focus }
        func loadThread(uri: String) async throws -> ConversationThread {
            if fails { throw StubError() }
            return ConversationThread(focus: focus, replies: [])
        }
    }

    /// Holds like and repost requests until the test answers them.
    private final class GatedInteractor: PostInteracting, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<String, Error>] = []
        private var calls: [String] = []
        var removeFails = false

        var pendingCount: Int { lock.withLock { waiting.count } }
        var callLog: [String] { lock.withLock { calls } }

        private func hold(_ call: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    calls.append(call)
                    waiting.append(continuation)
                }
            }
        }

        func answer(with result: Result<String, Error>) {
            let continuation = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
            continuation?.resume(with: result)
        }

        func like(uri: String, cid: String) async throws -> String { try await hold("like") }
        func removeLike(recordURI: String) async throws {
            lock.withLock { calls.append("removeLike \(recordURI)") }
            if removeFails { throw StubError() }
        }
        func repost(uri: String, cid: String) async throws -> String { try await hold("repost") }
        func removeRepost(recordURI: String) async throws { lock.withLock { calls.append("removeRepost") } }
        func deletePost(uri: String) async throws {}
    }

    private struct TimedOut: Error {}

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        guard condition() else {
            XCTFail("timed out waiting for the condition", file: file, line: line)
            throw TimedOut()
        }
    }

    private func sample(id: String = "p1", likeCount: Int = 3, viewerLikeURI: String? = nil) -> PostDisplay {
        PostDisplay(
            id: id, cid: "cid", authorDisplayName: "Alice", authorHandle: "alice.bsky.social",
            body: "hi", createdAt: Date(timeIntervalSince1970: 1_780_574_400),
            likeCount: likeCount, viewerLikeURI: viewerLikeURI
        )
    }

    /// The timeline shows `post`, the conversation `conversation` (a later or
    /// earlier copy of the same post), both loaded.
    private func makePair(
        _ post: PostDisplay, conversation: PostDisplay? = nil, interactor: PostInteracting
    ) async -> (TimelineViewModel, ThreadViewModel) {
        let interactions = SharedPostInteractions()
        let timeline = TimelineViewModel(loader: StubTimelineLoader(posts: [post]), interactor: interactor, interactions: interactions)
        let thread = ThreadViewModel(loader: StubThreadLoader(focus: conversation ?? post), uri: post.id, interactor: interactor, interactions: interactions)
        await timeline.load()
        await thread.load()
        return (timeline, thread)
    }

    func testALikeInTheTimelineShowsInTheConversation() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let (timeline, thread) = await makePair(post, interactor: interactor)

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        XCTAssertEqual(thread.focus?.isLiked, true)
        XCTAssertEqual(thread.focus?.likeCount, 4)
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value

        XCTAssertEqual(thread.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
        XCTAssertEqual(thread.focus?.likeCount, 4)
    }

    func testARepostInTheConversationShowsInTheTimeline() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let (timeline, thread) = await makePair(post, interactor: interactor)

        let repost = Task { await thread.toggleRepost(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        interactor.answer(with: .success("at://me/app.bsky.feed.repost/new"))
        await repost.value

        XCTAssertEqual(timeline.posts[0].viewerRepostURI, "at://me/app.bsky.feed.repost/new")
        XCTAssertEqual(timeline.posts[0].repostCount, 1)
    }

    func testAFailedLikeIsUndoneInBoth() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let (timeline, thread) = await makePair(post, interactor: interactor)

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        interactor.answer(with: .failure(StubError()))
        await like.value

        XCTAssertEqual(timeline.posts[0].isLiked, false)
        XCTAssertEqual(thread.focus?.isLiked, false)
        XCTAssertEqual(thread.focus?.likeCount, 3)
    }

    /// Liking from the conversation while the timeline's like is still being
    /// sent sends nothing more.
    func testALikeBeingSentFromOnePaneIsNotSentAgainFromTheOther() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let (timeline, thread) = await makePair(post, interactor: interactor)

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        // In a task, so a second like being sent cannot hold the test.
        let second = Task { await thread.toggleLike(post) }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(interactor.callLog, ["like"])
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        interactor.answer(with: .success("at://me/app.bsky.feed.like/second"))
        await like.value
        await second.value

        XCTAssertEqual(interactor.callLog, ["like"])
        XCTAssertEqual(thread.focus?.isLiked, true)
    }

    /// A conversation opened from a copy without the like being sent (a reply
    /// row elsewhere) shows the like until its thread loads, and if it fails.
    func testAPreviewOpenedWhileALikeIsBeingSentShowsIt() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let interactions = SharedPostInteractions()
        let timeline = TimelineViewModel(loader: StubTimelineLoader(posts: [post]), interactor: interactor, interactions: interactions)
        await timeline.load()

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        let opened = ThreadViewModel(loader: StubThreadLoader(focus: post), uri: post.id, interactor: interactor, interactions: interactions, preview: post)
        let adopted = ThreadViewModel(loader: StubThreadLoader(focus: post), uri: post.id, interactor: interactor, interactions: interactions)
        adopted.adoptPreview(post)
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value

        XCTAssertEqual(opened.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
        XCTAssertEqual(adopted.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
        XCTAssertEqual(opened.focus?.likeCount, 4)
    }

    /// A conversation opened while the timeline's like is being sent loads the
    /// server's copy without it, and shows the like anyway.
    func testAConversationLoadedWhileALikeIsBeingSentShowsIt() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let interactions = SharedPostInteractions()
        let timeline = TimelineViewModel(loader: StubTimelineLoader(posts: [post]), interactor: interactor, interactions: interactions)
        await timeline.load()

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        let thread = ThreadViewModel(loader: StubThreadLoader(focus: post), uri: post.id, interactor: interactor, interactions: interactions)
        await thread.load()
        XCTAssertEqual(thread.focus?.isLiked, true)
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value

        XCTAssertEqual(thread.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
        XCTAssertEqual(thread.focus?.likeCount, 4)
    }

    /// The conversation's placeholder, shown until its thread loads, follows too.
    func testTheConversationPreviewFollowsALike() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let interactions = SharedPostInteractions()
        let timeline = TimelineViewModel(loader: StubTimelineLoader(posts: [post]), interactor: interactor, interactions: interactions)
        await timeline.load()
        let thread = ThreadViewModel(loader: StubThreadLoader(focus: post), uri: post.id, interactor: interactor, interactions: interactions, preview: post)

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        XCTAssertEqual(thread.focus?.isLiked, true)
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value

        XCTAssertEqual(thread.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
    }

    /// The timeline shows the post liked, the conversation a newer copy without
    /// the like. A failed unlike from the timeline leaves the conversation as it was.
    func testAFailedUnlikeLeavesACopyThatWasNotLikedAlone() async throws {
        let interactor = GatedInteractor()
        interactor.removeFails = true
        let liked = sample(likeCount: 10, viewerLikeURI: "at://me/app.bsky.feed.like/a")
        let (timeline, thread) = await makePair(liked, conversation: sample(likeCount: 12), interactor: interactor)

        await timeline.toggleLike(liked)

        XCTAssertEqual(timeline.posts[0].viewerLikeURI, "at://me/app.bsky.feed.like/a")
        XCTAssertEqual(timeline.posts[0].likeCount, 10)
        XCTAssertEqual(thread.focus?.isLiked, false)
        XCTAssertEqual(thread.focus?.likeCount, 12)
    }

    /// The conversation still shows an older like record; liking again from the
    /// timeline makes the new record the one both would remove.
    func testANewLikeReplacesAnOlderRecordInTheOtherCopy() async throws {
        let interactor = GatedInteractor()
        let post = sample(likeCount: 3)
        let stale = sample(likeCount: 4, viewerLikeURI: "at://me/app.bsky.feed.like/old")
        let (timeline, thread) = await makePair(post, conversation: stale, interactor: interactor)

        let like = Task { await timeline.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value
        await thread.toggleLike(thread.focus!)

        XCTAssertEqual(interactor.callLog, ["like", "removeLike at://me/app.bsky.feed.like/new"])
    }

    /// Reloading a conversation shows the anchor as last shown, not the row it
    /// was opened from, until the thread arrives or when it fails.
    func testReloadingAConversationKeepsTheLikeShownMeanwhile() async throws {
        let interactor = GatedInteractor()
        let post = sample()
        let interactions = SharedPostInteractions()
        let loader = StubThreadLoader(focus: post)
        let thread = ThreadViewModel(loader: loader, uri: post.id, interactor: interactor, interactions: interactions, preview: post)
        await thread.load()
        let like = Task { await thread.toggleLike(post) }
        try await waitUntil { interactor.pendingCount == 1 }
        interactor.answer(with: .success("at://me/app.bsky.feed.like/new"))
        await like.value

        loader.fails = true
        await thread.load()

        XCTAssertEqual(thread.focus?.viewerLikeURI, "at://me/app.bsky.feed.like/new")
    }
}
