import XCTest

@MainActor
final class DockBadgeSettingsTests: XCTestCase {
    func testDockPreferenceInheritsSidebarOnceAndThenPersistsIndependently() throws {
        let suite = "DockBadgeSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "notifications.showsUnreadBadges")
        let settings = NotificationSettingsStore(defaults: defaults)
        XCTAssertFalse(settings.showsDockBadge)
        settings.showsUnreadBadges = true
        XCTAssertFalse(NotificationSettingsStore(defaults: defaults).showsDockBadge)
        settings.showsDockBadge = true
        settings.showsUnreadBadges = false
        let reloaded = NotificationSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.showsDockBadge)
        XCTAssertFalse(reloaded.showsUnreadBadges)
    }
}
