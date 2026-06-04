import XCTest
@testable import BlueskyCore

final class XRPCErrorTests: XCTestCase {
    func test_decodesErrorResponseWithMessage() throws {
        let json = Data(#"{"error":"InvalidRequest","message":"bad handle"}"#.utf8)

        let decoded = try JSONDecoder().decode(XRPCErrorResponse.self, from: json)

        XCTAssertEqual(decoded, XRPCErrorResponse(error: "InvalidRequest", message: "bad handle"))
    }

    func test_decodesErrorResponseWithoutMessage() throws {
        let json = Data(#"{"error":"ExpiredToken"}"#.utf8)

        let decoded = try JSONDecoder().decode(XRPCErrorResponse.self, from: json)

        XCTAssertEqual(decoded, XRPCErrorResponse(error: "ExpiredToken", message: nil))
    }
}
