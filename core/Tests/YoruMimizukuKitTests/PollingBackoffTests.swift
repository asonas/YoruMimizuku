import XCTest
@testable import YoruMimizukuKit

final class PollingBackoffTests: XCTestCase {
    func testNoFailuresUsesBaseInterval() {
        let backoff = PollingBackoff(base: .seconds(30))
        XCTAssertEqual(backoff.currentInterval, .seconds(30))
    }

    func testOneFailureDoublesTheInterval() {
        var backoff = PollingBackoff(base: .seconds(30))
        backoff.recordFailure()
        XCTAssertEqual(backoff.currentInterval, .seconds(60))
    }

    func testTwoFailuresQuadrupleTheInterval() {
        var backoff = PollingBackoff(base: .seconds(30))
        backoff.recordFailure()
        backoff.recordFailure()
        XCTAssertEqual(backoff.currentInterval, .seconds(120))
    }

    func testIntervalIsClampedToTheCap() {
        // base 30s -> cap is max(300s, 30*8=240s) = 300s. 30 * 2^4 = 480 > 300.
        var backoff = PollingBackoff(base: .seconds(30))
        for _ in 0..<4 { backoff.recordFailure() }
        XCTAssertEqual(backoff.currentInterval, .seconds(300))
    }

    func testCapIsEightTimesBaseWhenThatExceeds300s() {
        // base 60s -> cap is max(300s, 60*8=480s) = 480s.
        var backoff = PollingBackoff(base: .seconds(60))
        for _ in 0..<10 { backoff.recordFailure() }
        XCTAssertEqual(backoff.currentInterval, .seconds(480))
    }

    func testSuccessResetsToBaseInterval() {
        var backoff = PollingBackoff(base: .seconds(30))
        backoff.recordFailure()
        backoff.recordFailure()
        backoff.recordSuccess()
        XCTAssertEqual(backoff.currentInterval, .seconds(30))
    }

    func testLargeFailureStreakStaysAtCapWithoutOverflow() {
        var backoff = PollingBackoff(base: .seconds(30))
        for _ in 0..<1000 { backoff.recordFailure() }
        XCTAssertEqual(backoff.currentInterval, .seconds(300))
    }
}
