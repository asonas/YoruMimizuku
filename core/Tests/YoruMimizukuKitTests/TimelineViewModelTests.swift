import XCTest
@testable import YoruMimizukuKit

@MainActor
final class TimelineViewModelTests: XCTestCase {
    /// Returns a queued page per call so a test can script the initial load and
    /// subsequent loadMore/refresh fetches independently.
    private final class StubLoader: TimelineLoading, @unchecked Sendable {
        var pages: [Result<TimelinePage, Error>]
        private(set) var requestedCursors: [String?] = []
        init(pages: [Result<TimelinePage, Error>]) { self.pages = pages }

        convenience init(result: Result<[PostDisplay], Error>, cursor: String? = nil) {
            self.init(pages: [result.map { TimelinePage(posts: $0, cursor: cursor) }])
        }

        func loadPage(cursor: String?) async throws -> TimelinePage {
            requestedCursors.append(cursor)
            guard !pages.isEmpty else { return TimelinePage(posts: [], cursor: nil) }
            return try pages.removeFirst().get()
        }
    }

    private struct StubError: Error {}

    private final class FakeInteractor: PostInteracting, @unchecked Sendable {
        var likeResult: Result<String, Error> = .success("at://me/app.bsky.feed.like/new")
        var repostResult: Result<String, Error> = .success("at://me/app.bsky.feed.repost/new")
        var removeShouldFail = false
        var deleteShouldFail = false
        private(set) var likeCalls = 0
        private(set) var removeLikeCalls = 0
        private(set) var repostCalls = 0
        private(set) var deletePostCalls = 0
        private(set) var lastLikeUri: String?
        private(set) var lastLikeCid: String?
        private(set) var lastRemovedLikeURI: String?
        private(set) var lastDeletedPostURI: String?

        func like(uri: String, cid: String) async throws -> String {
            likeCalls += 1; lastLikeUri = uri; lastLikeCid = cid
            return try likeResult.get()
        }
        func removeLike(recordURI: String) async throws {
            removeLikeCalls += 1; lastRemovedLikeURI = recordURI
            if removeShouldFail { throw StubError() }
        }
        func repost(uri: String, cid: String) async throws -> String {
            repostCalls += 1
            return try repostResult.get()
        }
        func removeRepost(recordURI: String) async throws {
            if removeShouldFail { throw StubError() }
        }
        func deletePost(uri: String) async throws {
            deletePostCalls += 1; lastDeletedPostURI = uri
            if deleteShouldFail { throw StubError() }
        }
    }

    private func sample(
        id: String, cid: String = "cid", likeCount: Int = 0, viewerLikeURI: String? = nil
    ) -> PostDisplay {
        PostDisplay(
            id: id, cid: cid, authorDisplayName: "Alice", authorHandle: "alice.bsky.social",
            body: "hi", createdAt: Date(timeIntervalSince1970: 1_780_574_400),
            likeCount: likeCount, viewerLikeURI: viewerLikeURI
        )
    }

    func testToggleLikeOptimisticallyLikesThenConfirmsRecordURI() async {
        let interactor = FakeInteractor()
        let post = sample(id: "p1", cid: "c1", likeCount: 3)
        let vm = TimelineViewModel(loader: StubLoader(result: .success([post])), interactor: interactor)
        await vm.load()

        await vm.toggleLike(post)

        XCTAssertTrue(vm.posts[0].isLiked)
        XCTAssertEqual(vm.posts[0].likeCount, 4)
        XCTAssertEqual(vm.posts[0].viewerLikeURI, "at://me/app.bsky.feed.like/new")
        XCTAssertEqual(interactor.likeCalls, 1)
        XCTAssertEqual(interactor.lastLikeUri, "p1")
        XCTAssertEqual(interactor.lastLikeCid, "c1")
    }

    func testToggleLikeOnLikedPostUnlikesAndDeletesRecord() async {
        let interactor = FakeInteractor()
        let post = sample(id: "p1", likeCount: 5, viewerLikeURI: "at://me/app.bsky.feed.like/existing")
        let vm = TimelineViewModel(loader: StubLoader(result: .success([post])), interactor: interactor)
        await vm.load()

        await vm.toggleLike(post)

        XCTAssertFalse(vm.posts[0].isLiked)
        XCTAssertEqual(vm.posts[0].likeCount, 4)
        XCTAssertEqual(interactor.removeLikeCalls, 1)
        XCTAssertEqual(interactor.lastRemovedLikeURI, "at://me/app.bsky.feed.like/existing")
    }

    func testToggleLikeRollsBackWhenLikeFails() async {
        let interactor = FakeInteractor()
        interactor.likeResult = .failure(StubError())
        let post = sample(id: "p1", likeCount: 3)
        let vm = TimelineViewModel(loader: StubLoader(result: .success([post])), interactor: interactor)
        await vm.load()

        await vm.toggleLike(post)

        XCTAssertFalse(vm.posts[0].isLiked)
        XCTAssertEqual(vm.posts[0].likeCount, 3)
    }

    func testToggleRepostOptimisticallyRepostsThenConfirms() async {
        let interactor = FakeInteractor()
        let post = sample(id: "p1")
        let vm = TimelineViewModel(loader: StubLoader(result: .success([post])), interactor: interactor)
        await vm.load()

        await vm.toggleRepost(post)

        XCTAssertTrue(vm.posts[0].isReposted)
        XCTAssertEqual(vm.posts[0].repostCount, 1)
        XCTAssertEqual(vm.posts[0].viewerRepostURI, "at://me/app.bsky.feed.repost/new")
        XCTAssertEqual(interactor.repostCalls, 1)
    }

    func testDeletePostRemovesRowAndCallsInteractor() async {
        let interactor = FakeInteractor()
        let posts = [sample(id: "at://me/app.bsky.feed.post/a"), sample(id: "at://me/app.bsky.feed.post/b")]
        let vm = TimelineViewModel(loader: StubLoader(result: .success(posts)), interactor: interactor)
        await vm.load()

        await vm.deletePost(posts[0])

        XCTAssertEqual(vm.posts.map(\.id), ["at://me/app.bsky.feed.post/b"])
        XCTAssertEqual(interactor.deletePostCalls, 1)
        XCTAssertEqual(interactor.lastDeletedPostURI, "at://me/app.bsky.feed.post/a")
    }

    func testDeletePostRestoresRowOnFailure() async {
        let interactor = FakeInteractor()
        interactor.deleteShouldFail = true
        let posts = [sample(id: "p1"), sample(id: "p2")]
        let vm = TimelineViewModel(loader: StubLoader(result: .success(posts)), interactor: interactor)
        await vm.load()

        await vm.deletePost(posts[0])

        XCTAssertEqual(vm.posts.map(\.id), ["p1", "p2"])
    }

    func testDeletePostIsNoOpWithoutInteractor() async {
        let posts = [sample(id: "p1")]
        let vm = TimelineViewModel(loader: StubLoader(result: .success(posts)))
        await vm.load()

        await vm.deletePost(posts[0])

        XCTAssertEqual(vm.posts.map(\.id), ["p1"])
    }

    func testToggleLikeIsNoOpWithoutInteractor() async {
        let post = sample(id: "p1", likeCount: 3)
        let vm = TimelineViewModel(loader: StubLoader(result: .success([post])))
        await vm.load()

        await vm.toggleLike(post)

        XCTAssertFalse(vm.posts[0].isLiked)
        XCTAssertEqual(vm.posts[0].likeCount, 3)
    }

    func testInitialStateIsIdle() {
        let vm = TimelineViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.posts, [])
        XCTAssertFalse(vm.canLoadMore)
    }

    func testSuccessfulLoadReachesLoaded() async {
        let posts = [sample(id: "p1"), sample(id: "p2")]
        let loader = StubLoader(result: .success(posts), cursor: "c1")
        let vm = TimelineViewModel(loader: loader)

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(posts))
        XCTAssertEqual(vm.posts, posts)
        XCTAssertEqual(loader.requestedCursors, [nil])
        XCTAssertTrue(vm.canLoadMore)
    }

    func testFailedLoadReachesFailed() async {
        let vm = TimelineViewModel(loader: StubLoader(result: .failure(StubError())))

        await vm.load()

        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
        XCTAssertEqual(vm.posts, [])
    }

    func testLoadMoreAppendsOlderPageUsingCursor() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p3"), sample(id: "p4")], cursor: "c2"))
        ])
        let vm = TimelineViewModel(loader: loader)

        await vm.load()
        await vm.loadMore()

        XCTAssertEqual(vm.posts.map(\.id), ["p1", "p2", "p3", "p4"])
        XCTAssertEqual(loader.requestedCursors, [nil, "c1"])
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testLoadMoreIsNoOpWhenCursorExhausted() async {
        let loader = StubLoader(result: .success([sample(id: "p1")]), cursor: nil)
        let vm = TimelineViewModel(loader: loader)

        await vm.load()
        await vm.loadMore()

        XCTAssertEqual(loader.requestedCursors, [nil])
        XCTAssertFalse(vm.canLoadMore)
    }

    func testLoadMoreDropsDuplicatePosts() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p2"), sample(id: "p3")], cursor: "c2"))
        ])
        let vm = TimelineViewModel(loader: loader)

        await vm.load()
        await vm.loadMore()

        XCTAssertEqual(vm.posts.map(\.id), ["p1", "p2", "p3"])
    }

    /// A loader whose responses the test releases one by one, in any order, so a
    /// test can finish requests out of the order they started.
    private final class GatedLoader: TimelineLoading, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [(cursor: String?, resume: CheckedContinuation<TimelinePage, Error>)] = []
        private var cursors: [String?] = []

        var requestedCursors: [String?] { lock.withLock { cursors } }
        var pendingCount: Int { lock.withLock { waiting.count } }

        func loadPage(cursor: String?) async throws -> TimelinePage {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    cursors.append(cursor)
                    waiting.append((cursor, continuation))
                }
            }
        }

        /// Finish the oldest (or, with `newest`, the latest) pending request made
        /// with `cursor`.
        func release(cursor: String?, newest: Bool = false, with result: Result<TimelinePage, Error>) {
            let continuation: CheckedContinuation<TimelinePage, Error>? = lock.withLock {
                let matches = waiting.indices.filter { waiting[$0].cursor == cursor }
                guard let index = newest ? matches.last : matches.first else { return nil }
                return waiting.remove(at: index).resume
            }
            continuation?.resume(with: result)
        }

        /// Finish whatever request is pending, so a failing assertion never leaves
        /// the test awaiting a request it did not expect.
        func releaseAll(with result: Result<TimelinePage, Error>) {
            let pending = lock.withLock { () -> [CheckedContinuation<TimelinePage, Error>] in
                defer { waiting.removeAll() }
                return waiting.map(\.resume)
            }
            pending.forEach { $0.resume(with: result) }
        }
    }

    private struct TimedOut: Error {}

    /// Waits up to about a second; on timeout the test fails instead of going on
    /// to await a request that never started.
    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        guard condition() else {
            XCTFail("timed out waiting for the condition", file: file, line: line)
            throw TimedOut()
        }
    }

    // Two head refreshes in flight (polling plus the refresh after posting): the
    // one started first must not land after the newer one and push it down.
    func testEarlierRefreshFinishingLastIsDropped() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let initial = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "a")], cursor: "c1")))
        await initial.value

        let older = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 1 }
        let newer = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 2 }
        loader.release(cursor: nil, newest: true, with: .success(TimelinePage(posts: [sample(id: "c"), sample(id: "b"), sample(id: "a")], cursor: "x")))
        await newer.value
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "b"), sample(id: "a")], cursor: "y")))
        await older.value

        XCTAssertEqual(vm.posts.map(\.id), ["c", "b", "a"])
    }

    // Coming back to an author page after more than a page of new posts: the
    // fresh page does not touch the rows held, so it replaces them and its cursor
    // continues from there instead of skipping the posts in between.
    func testRefreshWithNoOverlapReplacesRowsAndCursor() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "old1"), sample(id: "old2")], cursor: "c-old")),
            .success(TimelinePage(posts: [sample(id: "new1"), sample(id: "new2")], cursor: "c-new"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()

        await vm.refresh()
        await vm.loadMore()

        XCTAssertEqual(vm.posts.map(\.id), ["new1", "new2"])
        XCTAssertEqual(loader.requestedCursors.last, "c-new")
    }

    // An older-page fetch started before such a replacement belongs to the rows
    // that were dropped, so its late page must not be appended.
    func testOlderPageStartedBeforeAReplacementIsDropped() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let initial = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "old1")], cursor: "c-old")))
        await initial.value

        let tail = Task { await vm.loadMore() }
        try await waitUntil { loader.pendingCount == 1 }
        let head = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 2 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "new1")], cursor: "c-new")))
        await head.value
        loader.release(cursor: "c-old", with: .success(TimelinePage(posts: [sample(id: "old2")], cursor: "c-older")))
        await tail.value

        XCTAssertEqual(vm.posts.map(\.id), ["new1"])
        let next = Task { await vm.loadMore() }
        try await waitUntil { loader.pendingCount == 1 }
        XCTAssertEqual(loader.requestedCursors.last, "c-new")
        loader.releaseAll(with: .success(TimelinePage(posts: [], cursor: nil)))
        await next.value
    }

    // A replacement applied by an earlier refresh must not drop a later refresh
    // that finishes afterwards.
    func testLaterRefreshAfterAReplacementIsStillApplied() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let initial = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "a")], cursor: "c-a")))
        await initial.value

        let earlier = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 1 }
        let later = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 2 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "b")], cursor: "c-b")))
        await earlier.value
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "c"), sample(id: "b")], cursor: "c-c")))
        await later.value

        XCTAssertEqual(vm.posts.map(\.id), ["c", "b"])
    }

    // After a replacement the new tail can fetch its next page at once, even
    // while the dropped fetch for the old rows has not come back yet.
    func testLoadMoreCanStartRightAfterAReplacement() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let initial = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "old1")], cursor: "c-old")))
        await initial.value

        let staleTail = Task { await vm.loadMore() }
        try await waitUntil { loader.pendingCount == 1 }
        let head = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 2 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "new1")], cursor: "c-new")))
        await head.value

        let freshTail = Task { await vm.loadMore() }
        try await waitUntil { loader.requestedCursors.contains("c-new") }
        loader.release(cursor: "c-old", with: .success(TimelinePage(posts: [sample(id: "old2")], cursor: "c-older")))
        await staleTail.value
        loader.release(cursor: "c-new", with: .success(TimelinePage(posts: [sample(id: "new2")], cursor: nil)))
        await freshTail.value

        XCTAssertEqual(vm.posts.map(\.id), ["new1", "new2"])
        XCTAssertFalse(vm.isLoadingMore)
        loader.releaseAll(with: .success(TimelinePage(posts: [], cursor: nil)))
    }

    // A feed that was empty adopts the first non-empty page's cursor, so its
    // second page can be reached.
    func testRefreshOfAnEmptyFeedAdoptsTheCursor() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [], cursor: nil)),
            .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p1")], cursor: "c1"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()

        await vm.refresh()

        XCTAssertEqual(vm.posts.map(\.id), ["p1"])
        XCTAssertTrue(vm.canLoadMore)
    }

    // Returning to an author page in the detail pane restarts its polling; the
    // pages already read further down must survive that restart.
    func testRestartingPollingKeepsPagesAlreadyLoaded() async throws {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p3"), sample(id: "p4")], cursor: "c2")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        await vm.loadMore()

        vm.startPolling(every: .seconds(3600))
        try await waitUntil { vm.posts.count == 5 }
        vm.stopPolling()
        await vm.loadMore()

        XCTAssertEqual(vm.posts.map(\.id), ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(loader.requestedCursors.last, "c2")
    }

    // Scrolling to the bottom of an author page right after returning to it can
    // finish an older-page fetch while the head refresh is still in flight.
    func testRefreshAndLoadMoreFinishingOutOfOrderKeepBothResults() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let initial = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p2")], cursor: "c1")))
        await initial.value

        let head = Task { await vm.refresh() }
        try await waitUntil { loader.pendingCount == 1 }
        let tail = Task { await vm.loadMore() }
        try await waitUntil { loader.pendingCount == 2 }
        loader.release(cursor: "c1", with: .success(TimelinePage(posts: [sample(id: "p3")], cursor: "c2")))
        await tail.value
        loader.release(cursor: nil, with: .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0")))
        await head.value

        XCTAssertEqual(vm.posts.map(\.id), ["p0", "p1", "p2", "p3"])
    }

    // Restarting polling while the first load is still in flight starts a second
    // load; the first one's late failure must not replace the newer result.
    func testLateResultOfAnEarlierLoadIsIgnored() async throws {
        let loader = GatedLoader()
        let vm = TimelineViewModel(loader: loader)
        let first = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 1 }
        let second = Task { await vm.load() }
        try await waitUntil { loader.pendingCount == 2 }

        loader.release(cursor: nil, newest: true, with: .success(TimelinePage(posts: [sample(id: "p1")], cursor: "c1")))
        await second.value
        loader.release(cursor: nil, with: .failure(StubError()))
        await first.value

        XCTAssertEqual(vm.posts.map(\.id), ["p1"])
    }

    func testRefreshMergesFreshPostsOnTop() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2"), sample(id: "p3")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p1"), sample(id: "p2")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)

        await vm.load()
        await vm.refresh()

        XCTAssertEqual(vm.posts.map(\.id), ["p1", "p2", "p3"])
    }

    func testRefreshKeepsCurrentFeedOnFailure() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p1")], cursor: "c1")),
            .failure(StubError())
        ])
        let vm = TimelineViewModel(loader: loader)

        await vm.load()
        await vm.refresh()

        XCTAssertEqual(vm.posts.map(\.id), ["p1"])
    }

    func testLoadReportsSuccessAndFailure() async {
        let ok = TimelineViewModel(loader: StubLoader(result: .success([sample(id: "p1")])))
        let okResult = await ok.load()
        XCTAssertTrue(okResult)

        let bad = TimelineViewModel(loader: StubLoader(result: .failure(StubError())))
        let badResult = await bad.load()
        XCTAssertFalse(badResult)
    }

    func testRefreshReportsSuccessAndFailure() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p1")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0")),
            .failure(StubError())
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()

        let okResult = await vm.refresh()
        XCTAssertTrue(okResult)

        let badResult = await vm.refresh()
        XCTAssertFalse(badResult)
    }

    func testInitialUnreadCountIsZero() {
        let vm = TimelineViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testFirstLoadTreatsExistingPostsAsSeen() async {
        let vm = TimelineViewModel(loader: StubLoader(result: .success([sample(id: "p1"), sample(id: "p2")])))
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testRefreshAddsToUnreadWhenInactive() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2"), sample(id: "p3")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()      // baseline: head is p2
        await vm.refresh()   // p0, p1 land above p2
        XCTAssertEqual(vm.unreadCount, 2)
    }

    func testMarkSeenResetsUnread() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 2)
        vm.markSeen()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testActiveTabStaysAtZeroOnRefresh() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1"), sample(id: "p2")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        vm.setActive(true)
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testDeactivatedTabAccumulatesUnread() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1"), sample(id: "p2")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        vm.setActive(true)    // marks seen at p2
        vm.setActive(false)   // now inactive; fresh posts should accumulate
        await vm.refresh()    // p0, p1 land above the seen head p2
        XCTAssertEqual(vm.unreadCount, 2)
    }
}
