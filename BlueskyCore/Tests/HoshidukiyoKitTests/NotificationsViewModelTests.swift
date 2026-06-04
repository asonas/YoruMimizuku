import XCTest
import BlueskyCore
@testable import HoshidukiyoKit

@MainActor
final class NotificationsViewModelTests: XCTestCase {
    private final class StubLoader: NotificationsLoading, @unchecked Sendable {
        var result: Result<[NotificationDisplay], Error>
        private(set) var loadCount = 0
        init(result: Result<[NotificationDisplay], Error>) { self.result = result }
        func loadLatest() async throws -> [NotificationDisplay] {
            loadCount += 1
            return try result.get()
        }
    }

    private struct StubError: Error {}

    private func sample(id: String) -> NotificationDisplay {
        NotificationDisplay(
            id: id, reason: .like, authorDisplayName: "Bob", authorHandle: "bob.bsky.social",
            createdAt: Date(timeIntervalSince1970: 1_780_574_400)
        )
    }

    func testInitialStateIsIdle() {
        let vm = NotificationsViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.items, [])
    }

    func testSuccessfulLoadReachesLoaded() async {
        let items = [sample(id: "n1"), sample(id: "n2")]
        let loader = StubLoader(result: .success(items))
        let vm = NotificationsViewModel(loader: loader)

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(items))
        XCTAssertEqual(vm.items, items)
        XCTAssertEqual(loader.loadCount, 1)
    }

    func testFailedLoadReachesFailed() async {
        let vm = NotificationsViewModel(loader: StubLoader(result: .failure(StubError())))

        await vm.load()

        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
        XCTAssertEqual(vm.items, [])
    }
}
