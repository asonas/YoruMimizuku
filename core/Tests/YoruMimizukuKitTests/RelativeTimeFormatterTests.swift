import XCTest
@testable import YoruMimizukuKit

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

    /// The desktop prototype writes times in Japanese ("2分", "3時間").
    func testJapaneseStyle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let f = RelativeTimeFormatter(style: .japanese)
        XCTAssertEqual(f.string(for: now, now: now), "今")
        XCTAssertEqual(f.string(for: now.addingTimeInterval(-30), now: now), "30秒")
        XCTAssertEqual(f.string(for: now.addingTimeInterval(-120), now: now), "2分")
        XCTAssertEqual(f.string(for: now.addingTimeInterval(-3 * 3600), now: now), "3時間")
        XCTAssertEqual(f.string(for: now.addingTimeInterval(-2 * 86400), now: now), "2日")
    }
}
