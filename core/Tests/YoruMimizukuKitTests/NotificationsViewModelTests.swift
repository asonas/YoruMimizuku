import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

@MainActor
final class NotificationsViewModelTests: XCTestCase {
    private final class StubLoader: NotificationsLoading, @unchecked Sendable {
        var result: Result<[NotificationGroup], Error>
        private(set) var loadCount = 0
        init(result: Result<[NotificationGroup], Error>) { self.result = result }
        func loadLatest() async throws -> [NotificationGroup] {
            loadCount += 1
            return try result.get()
        }
    }

    private struct StubError: Error {}

    private func sample(id: String) -> NotificationGroup {
        NotificationGroup(
            id: id, reason: .like,
            actors: [.init(displayName: "Bob", handle: "bob.bsky.social", avatarURL: nil)],
            subjectURI: "at://post/\(id)",
            latestCreatedAt: Date(timeIntervalSince1970: 1_780_574_400),
            isRead: false
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
