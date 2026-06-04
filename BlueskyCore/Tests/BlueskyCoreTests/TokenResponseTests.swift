import XCTest
@testable import BlueskyCore

final class TokenResponseTests: XCTestCase {
    func testDecodesFullTokenResponse() throws {
        let json = ##"""
        {
          "access_token": "atk-123",
          "token_type": "DPoP",
          "refresh_token": "rtk-456",
          "expires_in": 3600,
          "scope": "atproto transition:generic",
          "sub": "did:plc:abc123"
        }
        """##
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "atk-123")
        XCTAssertEqual(response.tokenType, "DPoP")
        XCTAssertEqual(response.refreshToken, "rtk-456")
        XCTAssertEqual(response.expiresIn, 3600)
        XCTAssertEqual(response.scope, "atproto transition:generic")
        XCTAssertEqual(response.sub, "did:plc:abc123")
    }

    func testDecodesWhenOptionalFieldsAbsent() throws {
        // refresh_token, expires_in, scope are optional; access_token/token_type/sub required.
        let json = ##"{"access_token":"atk","token_type":"DPoP","sub":"did:plc:x"}"##
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "atk")
        XCTAssertNil(response.refreshToken)
        XCTAssertNil(response.expiresIn)
        XCTAssertNil(response.scope)
        XCTAssertEqual(response.sub, "did:plc:x")
    }
}
