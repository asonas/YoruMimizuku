import XCTest

final class LaunchUpdatePromptTests: XCTestCase {
    func testFreshPromptIsNotPending() {
        var prompt = LaunchUpdatePrompt()

        XCTAssertFalse(prompt.consume())
    }

    func testArmedPromptIsConsumedExactlyOnce() {
        var prompt = LaunchUpdatePrompt()

        prompt.arm()

        XCTAssertTrue(prompt.consume())
        XCTAssertFalse(prompt.consume())
    }
}
