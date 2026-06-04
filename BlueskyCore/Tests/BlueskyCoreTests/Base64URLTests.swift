import XCTest
@testable import BlueskyCore

final class Base64URLTests: XCTestCase {
    func test_encode_usesURLAlphabetAndStripsPadding() {
        // 0xFB 0xFF produce '+' and '/' and padding in standard base64 ("+/8=").
        let data = Data([0xFB, 0xFF])
        XCTAssertEqual(Base64URL.encode(data), "-_8")
    }

    func test_decode_roundTripsArbitraryBytes() throws {
        let original = Data([0x00, 0x10, 0xFB, 0xFF, 0xA5, 0x7C])
        let encoded = Base64URL.encode(original)
        let decoded = try XCTUnwrap(Base64URL.decode(encoded))
        XCTAssertEqual(decoded, original)
    }

    func test_decode_returnsNilForInvalidInput() {
        XCTAssertNil(Base64URL.decode("!!!not base64!!!"))
    }
}
