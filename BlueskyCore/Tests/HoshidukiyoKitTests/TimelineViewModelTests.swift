import XCTest
@testable import HoshidukiyoKit

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

    private func sample(id: String) -> PostDisplay {
        PostDisplay(
            id: id, authorDisplayName: "Alice", authorHandle: "alice.bsky.social",
            body: "hi", createdAt: Date(timeIntervalSince1970: 1_780_574_400)
        )
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
}
