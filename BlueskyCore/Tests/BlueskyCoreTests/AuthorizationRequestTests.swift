import XCTest
@testable import BlueskyCore

final class AuthorizationRequestTests: XCTestCase {
    func testDecodesPushedAuthorizationResponse() throws {
        let json = ##"{"request_uri":"urn:ietf:params:oauth:request_uri:abc123","expires_in":90}"##
        let response = try JSONDecoder().decode(
            PushedAuthorizationResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.requestURI, "urn:ietf:params:oauth:request_uri:abc123")
        XCTAssertEqual(response.expiresIn, 90)
    }
}
