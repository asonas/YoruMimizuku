import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

final class RichTextSegmentTests: XCTestCase {
    func testPlainTextWithoutFacetsIsOneTextSegment() {
        let segments = RichText.segments(text: "hello world", facets: [])

        XCTAssertEqual(segments.map(\.kind), [.text])
        XCTAssertEqual(segments.map(\.text), ["hello world"])
        XCTAssertNil(segments[0].url)
    }

    func testLinkFacetSplitsTextIntoSegments() {
        // "see https://example.com now"
        //  0123 4 ......................23 24
        let text = "see https://example.com now"
        let facets = [Facet(byteStart: 4, byteEnd: 23, features: [.link(uri: "https://example.com")])]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text, .link, .text])
        XCTAssertEqual(segments.map(\.text), ["see ", "https://example.com", " now"])
        XCTAssertEqual(segments[1].url, URL(string: "https://example.com"))
    }

    func testTagFacetUsesHashtagURL() {
        let text = "love #swift"
        let facets = [Facet(byteStart: 5, byteEnd: 11, features: [.tag(tag: "swift")])]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text, .tag])
        XCTAssertEqual(segments[1].text, "#swift")
        XCTAssertEqual(segments[1].url, URL(string: "https://bsky.app/hashtag/swift"))
    }

    func testMentionFacetUsesProfileURL() {
        let text = "hi @bob.bsky.social"
        let facets = [Facet(byteStart: 3, byteEnd: 19, features: [.mention(did: "did:plc:bob")])]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text, .mention])
        XCTAssertEqual(segments[1].text, "@bob.bsky.social")
        XCTAssertEqual(segments[1].url, URL(string: "https://bsky.app/profile/did:plc:bob"))
    }

    func testByteOffsetsRespectMultibyteText() {
        // The "🦉" emoji is 4 UTF-8 bytes; the link must still slice correctly.
        let text = "🦉 https://example.com"
        let prefixBytes = "🦉 ".utf8.count // 5
        let linkBytes = "https://example.com".utf8.count
        let facets = [Facet(
            byteStart: prefixBytes,
            byteEnd: prefixBytes + linkBytes,
            features: [.link(uri: "https://example.com")]
        )]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text, .link])
        XCTAssertEqual(segments[0].text, "🦉 ")
        XCTAssertEqual(segments[1].text, "https://example.com")
    }

    func testOutOfRangeFacetIsIgnored() {
        let text = "short"
        let facets = [Facet(byteStart: 0, byteEnd: 999, features: [.link(uri: "https://x")])]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text])
        XCTAssertEqual(segments.map(\.text), ["short"])
    }

    func testFacetWithoutSupportedFeatureFallsBackToText() {
        let text = "abc"
        let facets = [Facet(byteStart: 0, byteEnd: 3, features: [])]

        let segments = RichText.segments(text: text, facets: facets)

        XCTAssertEqual(segments.map(\.kind), [.text])
        XCTAssertEqual(segments.map(\.text), ["abc"])
    }

    func testHashtagFromURLExtractsTag() {
        let url = URL(string: "https://bsky.app/hashtag/swift")!
        XCTAssertEqual(RichText.hashtag(from: url), "swift")
    }

    func testHashtagFromURLDecodesMultibyteTag() {
        // The tag-building side percent-encodes; the reverse must decode it.
        let encoded = "猫".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://bsky.app/hashtag/\(encoded)")!
        XCTAssertEqual(RichText.hashtag(from: url), "猫")
    }

    func testHashtagFromNonHashtagURLIsNil() {
        XCTAssertNil(RichText.hashtag(from: URL(string: "https://bsky.app/profile/did:plc:bob")!))
        XCTAssertNil(RichText.hashtag(from: URL(string: "https://example.com/page")!))
    }

    func testMentionDIDExtractsDIDFromProfileURL() {
        let url = URL(string: "https://bsky.app/profile/did:plc:abc123")!
        XCTAssertEqual(RichText.mentionDID(from: url), "did:plc:abc123")
    }

    func testMentionDIDExtractsHandleFromProfileURL() {
        let url = URL(string: "https://bsky.app/profile/alice.bsky.social")!
        XCTAssertEqual(RichText.mentionDID(from: url), "alice.bsky.social")
    }

    func testMentionDIDIsNilForPostPermalink() {
        let url = URL(string: "https://bsky.app/profile/did:plc:abc123/post/3kabc")!
        XCTAssertNil(RichText.mentionDID(from: url))
    }

    func testMentionDIDIsNilForHashtagURL() {
        let url = URL(string: "https://bsky.app/hashtag/swift")!
        XCTAssertNil(RichText.mentionDID(from: url))
    }

    func testMentionDIDIsNilForForeignHost() {
        let url = URL(string: "https://example.com/profile/did:plc:abc123")!
        XCTAssertNil(RichText.mentionDID(from: url))
    }
}
