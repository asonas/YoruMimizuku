import XCTest
@testable import YoruMimizukuKit

final class WindowTitleTests: XCTestCase {
    func testComposeJoinsTabAndHandle() {
        XCTAssertEqual(WindowTitle.compose(tabTitle: "ホーム", accountHandle: "asonas.bsky.social"),
                       "ホーム — @asonas.bsky.social")
    }

    func testComposeOmitsEmptyHandle() {
        XCTAssertEqual(WindowTitle.compose(tabTitle: "ホーム", accountHandle: ""), "ホーム")
    }

    func testComposeDoesNotDoubleAtPrefix() {
        XCTAssertEqual(WindowTitle.compose(tabTitle: "ホーム", accountHandle: "@asonas.bsky.social"),
                       "ホーム — @asonas.bsky.social")
    }
}
