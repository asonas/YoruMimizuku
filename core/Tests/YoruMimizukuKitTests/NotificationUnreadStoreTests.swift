import XCTest
@testable import YoruMimizukuKit

private actor ReadService: NotificationReadService {
    var counts = ["A": 2, "B": 3]
    var offline = false
    var rejectsWrites = false
    var sent: [Date] = []
    func setOffline(_ value: Bool) { offline = value }
    func rejectWrites(afterExternalReadFor did: String) {
        rejectsWrites = true
        counts[did] = 0
    }
    func unreadCount(for did: String) throws -> Int {
        if offline { throw URLError(.notConnectedToInternet) }
        return counts[did] ?? 0
    }
    func updateSeen(for did: String, through date: Date) throws {
        sent.append(date)
        if offline || rejectsWrites { throw URLError(.notConnectedToInternet) }
        counts[did] = 1 // One notification arrived after the displayed page.
    }
}

@MainActor
final class NotificationUnreadStoreTests: XCTestCase {
    func testFailedWriteStillReflectsReadOnAnotherDeviceWhenCountIsAvailable() async {
        let service = ReadService()
        let store = NotificationUnreadStore(service: service)
        store.open("B", window: UUID())
        await store.refresh("B")
        await service.rejectWrites(afterExternalReadFor: "B")
        await store.markDisplayed("B", through: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(store.counts["B"], 0)
    }

    func testFailedMarkPreservesCountAndRetriesOnlyThroughDisplayedPage() async {
        let service = ReadService()
        let store = NotificationUnreadStore(service: service)
        store.open("B", window: UUID())
        await store.refresh("B")
        let boundary = Date(timeIntervalSince1970: 100)
        await service.setOffline(true)
        await store.markDisplayed("B", through: boundary)
        XCTAssertEqual(store.counts["B"], 3)
        await service.setOffline(false)
        await store.refresh("B")
        XCTAssertEqual(store.counts["B"], 1)
        await store.markDisplayed("B", through: boundary.addingTimeInterval(-30))
        let sent = await service.sent
        XCTAssertEqual(sent, [boundary, boundary])
    }

    func testCountsEachOpenAccountOnceAndKeepsLastKnownOnFailure() async {
        let service = ReadService()
        let store = NotificationUnreadStore(service: service)
        let first = UUID(), second = UUID(), third = UUID()
        store.open("A", window: first)
        store.open("A", window: second)
        store.open("B", window: third)
        await store.refresh("A")
        await store.refresh("B")
        XCTAssertEqual(store.counts, ["A": 2, "B": 3])
        await service.setOffline(true)
        store.open("C", window: UUID())
        await store.refresh("C")
        await store.refresh("B")
        XCTAssertEqual(store.counts, ["A": 2, "B": 3])
        store.close("A", window: first)
        XCTAssertEqual(store.counts["A"], 2)
        store.close("A", window: second)
        XCTAssertEqual(store.counts, ["B": 3])
    }
}
