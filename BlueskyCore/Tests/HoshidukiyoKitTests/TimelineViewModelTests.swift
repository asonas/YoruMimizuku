import XCTest
@testable import HoshidukiyoKit

@MainActor
final class TimelineViewModelTests: XCTestCase {
    private final class StubLoader: TimelineLoading, @unchecked Sendable {
        var result: Result<[PostDisplay], Error>
        private(set) var loadCount = 0
        init(result: Result<[PostDisplay], Error>) { self.result = result }
        func loadLatest() async throws -> [PostDisplay] {
            loadCount += 1
            return try result.get()
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
    }

    func testSuccessfulLoadReachesLoaded() async {
        let posts = [sample(id: "p1"), sample(id: "p2")]
        let loader = StubLoader(result: .success(posts))
        let vm = TimelineViewModel(loader: loader)

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(posts))
        XCTAssertEqual(vm.posts, posts)
        XCTAssertEqual(loader.loadCount, 1)
    }

    func testFailedLoadReachesFailed() async {
        let vm = TimelineViewModel(loader: StubLoader(result: .failure(StubError())))

        await vm.load()

        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
        XCTAssertEqual(vm.posts, [])
    }
}
