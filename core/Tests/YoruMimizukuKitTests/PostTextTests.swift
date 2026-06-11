import XCTest
@testable import YoruMimizukuKit

final class PostTextTests: XCTestCase {
    func testRemovesTrailingNewlines() {
        XCTAssertEqual(PostText.trimmingTrailingWhitespace(of: "hello\n\n"), "hello")
    }

    func testPreservesInteriorBreaksWhileDroppingTrailingBlankLines() {
        XCTAssertEqual(
            PostText.trimmingTrailingWhitespace(of: "line1\n\nline2\n \n"),
            "line1\n\nline2"
        )
    }

    func testRemovesTrailingSpacesAndTabs() {
        XCTAssertEqual(PostText.trimmingTrailingWhitespace(of: "hi \t "), "hi")
    }

    func testAllWhitespaceBecomesEmpty() {
        XCTAssertEqual(PostText.trimmingTrailingWhitespace(of: "  \n\t\n"), "")
    }

    func testTextWithoutTrailingWhitespaceIsUnchanged() {
        XCTAssertEqual(PostText.trimmingTrailingWhitespace(of: "no trailing"), "no trailing")
    }
}
