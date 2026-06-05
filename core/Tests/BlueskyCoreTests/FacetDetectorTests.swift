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

extension FacetDetectorTests {
    func testDetectsHashtag() {
        let facets = FacetDetector.detect(text: "hello #swift world")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .tag(tag: "swift"))
        XCTAssertEqual(facets[0].byteStart, 6)
        XCTAssertEqual(facets[0].byteEnd, 12)
    }

    func testIgnoresNumericOnlyHashtag() {
        XCTAssertTrue(FacetDetector.detect(text: "code #123 here").isEmpty)
    }

    func testHashtagByteOffsetsWithMultibytePrefix() {
        // "あ" is 3 UTF-8 bytes; the tag starts after it plus a space.
        let facets = FacetDetector.detect(text: "あ #tag")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .tag(tag: "tag"))
        XCTAssertEqual(facets[0].byteStart, 4)
        XCTAssertEqual(facets[0].byteEnd, 8)
    }
}

extension FacetDetectorTests {
    func testDetectsMentionCandidate() {
        let facets = FacetDetector.detect(text: "hi @alice.bsky.social !")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .mentionCandidate(handle: "alice.bsky.social"))
        XCTAssertEqual(facets[0].byteStart, 3)
        XCTAssertEqual(facets[0].byteEnd, 21)
    }

    func testSortsMixedFacetsByByteStart() {
        let facets = FacetDetector.detect(text: "@bob.test #tag https://x.io")
        XCTAssertEqual(facets.map(\.feature), [
            .mentionCandidate(handle: "bob.test"),
            .tag(tag: "tag"),
            .link(uri: "https://x.io"),
        ])
    }
}
