import XCTest
@testable import BlueskyCore

final class FacetDetectorTests: XCTestCase {
    func testDetectsBareLinkWithByteOffsets() {
        let text = "see https://example.com now"
        let facets = FacetDetector.detect(text: text)
        XCTAssertEqual(facets.count, 1)
        let f = facets[0]
        XCTAssertEqual(f.byteStart, 4)
        XCTAssertEqual(f.byteEnd, 23)
        XCTAssertEqual(f.feature, .link(uri: "https://example.com"))
    }

    func testTrimsTrailingPunctuationFromLink() {
        let text = "(https://example.com/path)."
        let facets = FacetDetector.detect(text: text)
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .link(uri: "https://example.com/path"))
    }
}
