import XCTest
@testable import YoruMimizuku

final class UpdateChannelStoreTests: XCTestCase {
    func testStableChannelUsesStableAppcastURL() throws {
        XCTAssertEqual(
            UpdateChannel.stable.feedURL,
            URL(string: "https://asonas.github.io/YoruMimizuku/appcast.xml")
        )
    }

    func testDevelopmentChannelUsesDevelopmentAppcastURL() throws {
        XCTAssertEqual(
            UpdateChannel.development.feedURL,
            URL(string: "https://asonas.github.io/YoruMimizuku/appcast-dev.xml")
        )
    }

    func testStoreDefaultsToStableWhenNoValueExists() throws {
        let suiteName = "UpdateChannelStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UpdateChannelStore(defaults: defaults)

        XCTAssertEqual(store.channel, .stable)
    }

    func testStorePersistsSelectedChannel() throws {
        let suiteName = "UpdateChannelStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var store = UpdateChannelStore(defaults: defaults)

        store.channel = .development

        XCTAssertEqual(UpdateChannelStore(defaults: defaults).channel, .development)
    }
}
