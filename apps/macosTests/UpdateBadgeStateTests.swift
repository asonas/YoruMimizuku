import XCTest

final class UpdateBadgeStateTests: XCTestCase {
    func testBackgroundFoundUpdateShowsBadge() {
        var state = UpdateBadgeState()

        state.scheduledUpdateFound()

        XCTAssertTrue(state.updateAvailable)
    }

    func testUpdateSessionFinishClearsBadge() {
        var state = UpdateBadgeState(updateAvailable: true)

        state.updateSessionFinished()

        XCTAssertFalse(state.updateAvailable)
    }

    func testVersionDisplayIncludesBuildNumber() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "0.6.0", build: "4"),
            "v0.6.0 (4)"
        )
    }

    func testVersionDisplayOmitsEmptyBuildNumber() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "0.6.0", build: ""),
            "v0.6.0"
        )
    }

    func testVersionDisplayDoesNotDuplicateVPrefix() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "v0.7.0-dev.1", build: "5"),
            "v0.7.0-dev.1 (5)"
        )
    }
}
