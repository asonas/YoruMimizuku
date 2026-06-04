import XCTest
@testable import HoshidukiyoKit

final class RelativeTimeFormatterTests: XCTestCase {
    let formatter = RelativeTimeFormatter()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func string(secondsAgo: Int) -> String {
        formatter.string(for: now.addingTimeInterval(TimeInterval(-secondsAgo)), now: now)
    }

    func test_underFiveSecondsIsNow() {
        XCTAssertEqual(string(secondsAgo: 0), "now")
        XCTAssertEqual(string(secondsAgo: 4), "now")
    }

    func test_secondsMinutesHoursDays() {
        XCTAssertEqual(string(secondsAgo: 30), "30s")
        XCTAssertEqual(string(secondsAgo: 120), "2m")
        XCTAssertEqual(string(secondsAgo: 3 * 3600), "3h")
        XCTAssertEqual(string(secondsAgo: 2 * 86_400), "2d")
    }

    func test_futureDatesClampToNow() {
        XCTAssertEqual(formatter.string(for: now.addingTimeInterval(60), now: now), "now")
    }
}
