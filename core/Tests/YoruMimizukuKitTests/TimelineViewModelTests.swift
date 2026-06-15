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
