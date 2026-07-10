import XCTest

/// Exercises the iPad `NotificationSettingsStore` persistence and interval
/// snapping. The test bundle compiles `apps/ipados/NotificationSettings.swift`
/// directly (listed in the `YoruMimizukuPadTests` sources), so the internal
/// store type is visible without `@testable import`.
@MainActor
final class NotificationSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "NotificationSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsWhenNothingStored() {
        let store = NotificationSettingsStore(defaults: defaults)
        XCTAssertEqual(store.pollIntervalSeconds, NotificationSettingsStore.defaultIntervalSeconds)
        XCTAssertTrue(store.showsUnreadBadges)
    }

    func testSnapsOutOfSetIntervalToNearestChoice() {
        // 100s is closest to the 60s choice (Δ40) rather than 300s (Δ200) or 30s (Δ70).
        defaults.set(100, forKey: "notifications.pollIntervalSeconds")
        let store = NotificationSettingsStore(defaults: defaults)
        XCTAssertEqual(store.pollIntervalSeconds, 60)
        XCTAssertTrue(NotificationSettingsStore.intervalChoices.contains(store.pollIntervalSeconds))
    }

    func testPersistsIntervalAndBadgeToggle() {
        let store = NotificationSettingsStore(defaults: defaults)
        store.pollIntervalSeconds = 15
        store.showsUnreadBadges = false

        let reloaded = NotificationSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.pollIntervalSeconds, 15)
        XCTAssertFalse(reloaded.showsUnreadBadges)
    }
}
