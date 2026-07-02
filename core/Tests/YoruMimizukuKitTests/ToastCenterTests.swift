import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ToastCenterTests: XCTestCase {
    func testShowSetsCurrentMessage() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("リンクをコピーしました")
        XCTAssertEqual(center.current?.text, "リンクをコピーしました")
    }

    func testSecondShowReplacesTheFirst() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("first")
        let firstID = center.current?.id
        center.show("second")
        XCTAssertEqual(center.current?.text, "second")
        XCTAssertNotEqual(center.current?.id, firstID)
    }

    func testDismissClearsCurrent() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("hi")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testExpireOnlyClearsWhenTokenMatchesCurrent() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("first")
        let firstID = center.current!.id
        center.show("second")
        // A stale expiry from the first toast must not clear the second.
        center.expire(token: firstID)
        XCTAssertEqual(center.current?.text, "second")
        // The matching expiry clears it.
        center.expire(token: center.current!.id)
        XCTAssertNil(center.current)
    }
}
