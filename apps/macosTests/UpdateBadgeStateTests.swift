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
            "0.6.0 (4)"
        )
    }

    func testVersionDisplayOmitsEmptyBuildNumber() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "0.6.0", build: ""),
            "0.6.0"
        )
    }
}
