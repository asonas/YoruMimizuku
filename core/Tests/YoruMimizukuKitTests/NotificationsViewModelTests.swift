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

    func testLoadReportsSuccessAndFailure() async {
        let ok = NotificationsViewModel(loader: StubLoader(result: .success([sample(id: "n1")])))
        let okResult = await ok.load()
        XCTAssertTrue(okResult)

        let bad = NotificationsViewModel(loader: StubLoader(result: .failure(StubError())))
        let badResult = await bad.load()
        XCTAssertFalse(badResult)
    }

    func testRefreshReportsSuccessAndFailure() async {
        let loader = StubLoader(result: .success([sample(id: "n1")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()

        let okResult = await vm.refresh()
        XCTAssertTrue(okResult)

        loader.result = .failure(StubError())
        let badResult = await vm.refresh()
        XCTAssertFalse(badResult)
    }

    func testInitialUnreadCountIsZero() {
        let vm = NotificationsViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testFirstLoadTreatsExistingNotificationsAsSeen() async {
        let vm = NotificationsViewModel(loader: StubLoader(result: .success([sample(id: "n1"), sample(id: "n2")])))
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testRefreshAddsToUnreadWhenInactive() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()                                   // baseline: head is n2
        loader.result = .success([sample(id: "n0"), sample(id: "n1"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 2)
    }

    func testMarkSeenResetsUnread() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()
        loader.result = .success([sample(id: "n0"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 1)
        vm.markSeen()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testActiveTabStaysAtZeroOnRefresh() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()
        vm.setActive(true)
        loader.result = .success([sample(id: "n0"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    /// Holds the second call (the first refresh) until `release()`, so a later
    /// refresh can finish first.
    private actor HeldSecondCallLoader: NotificationsLoading {
        private var calls = 0
        private var gate: CheckedContinuation<Void, Never>?
        private var parked: CheckedContinuation<Void, Never>?
        let pages: [[NotificationGroup]]
        init(pages: [[NotificationGroup]]) { self.pages = pages }

        func loadLatest() async throws -> [NotificationGroup] {
            calls += 1
            let page = pages[min(calls, pages.count) - 1]
            if calls == 2 {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    parked?.resume()
                    parked = nil
                }
            }
            return page
        }

        func waitUntilParked() async {
            if gate != nil { return }
            await withCheckedContinuation { parked = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }

    /// ⌘R during a poll can overlap two refreshes; the older answer must not
    /// replace the newer one.
    func testAnOlderRefreshFinishingLastDoesNotOverwriteANewerOne() async {
        let loader = HeldSecondCallLoader(pages: [[sample(id: "n1")], [sample(id: "old")], [sample(id: "new")]])
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()

        let older = Task { await vm.refresh() }
        await loader.waitUntilParked()
        await vm.refresh()
        await loader.release()
        _ = await older.value

        XCTAssertEqual(vm.items.map(\.id), ["new"])
    }

    /// Holds the first call (the initial load) until `release()`.
    private actor HeldFirstCallLoader: NotificationsLoading {
        private var calls = 0
        private var gate: CheckedContinuation<Void, Never>?
        private var parked: CheckedContinuation<Void, Never>?
        let pages: [Result<[NotificationGroup], Error>]
        init(pages: [Result<[NotificationGroup], Error>]) { self.pages = pages }

        func loadLatest() async throws -> [NotificationGroup] {
            calls += 1
            let page = pages[min(calls, pages.count) - 1]
            if calls == 1 {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    parked?.resume()
                    parked = nil
                }
            }
            return try page.get()
        }

        func waitUntilParked() async {
            if gate != nil { return }
            await withCheckedContinuation { parked = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }

    /// ⌘R while the first load is still out: the first load answering last must
    /// not replace (or fail over) the newer list.
    func testAFirstLoadFinishingAfterANewerRefreshIsDropped() async {
        let loader = HeldFirstCallLoader(pages: [.failure(StubError()), .success([sample(id: "new")])])
        let vm = NotificationsViewModel(loader: loader)

        let first = Task { await vm.load() }
        await loader.waitUntilParked()
        await vm.refresh()
        await loader.release()
        _ = await first.value

        XCTAssertEqual(vm.items.map(\.id), ["new"])
    }

    /// A later refresh that fails must not discard an earlier one that succeeded.
    func testAFailedLaterRefreshKeepsAnEarlierSuccess() async {
        let loader = HeldSecondCallLoader(pages: [[sample(id: "n1")], [sample(id: "polled")]])
        let failing = FailAfterLoader(inner: loader)
        let vm = NotificationsViewModel(loader: failing)
        await vm.load()

        let poll = Task { await vm.refresh() }
        await loader.waitUntilParked()
        await vm.refresh()
        await loader.release()
        _ = await poll.value

        XCTAssertEqual(vm.items.map(\.id), ["polled"])
    }

    /// Passes the first two calls to `inner`, then fails.
    private actor FailAfterLoader: NotificationsLoading {
        let inner: HeldSecondCallLoader
        private var calls = 0
        init(inner: HeldSecondCallLoader) { self.inner = inner }
        func loadLatest() async throws -> [NotificationGroup] {
            calls += 1
            if calls > 2 { throw StubError() }
            return try await inner.loadLatest()
        }
    }
}
