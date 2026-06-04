import XCTest
@testable import BlueskyCore

final class FormURLEncoderTests: XCTestCase {
    func testEncodesPairsAsKeyValueJoinedByAmpersand() {
        let data = FormURLEncoder.encode([("a", "1"), ("b", "2")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "a=1&b=2")
    }

    func testPercentEncodesSpacesAndReservedCharacters() {
        // scope value contains a space; client_id contains ':' and '/'.
        let data = FormURLEncoder.encode([
            ("scope", "atproto transition:generic"),
            ("client_id", "https://ason.as/x")
        ])
        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            "scope=atproto%20transition%3Ageneric&client_id=https%3A%2F%2Fason.as%2Fx"
        )
    }

    func testEmptyInputProducesEmptyData() {
        XCTAssertEqual(FormURLEncoder.encode([]), Data())
    }
}
