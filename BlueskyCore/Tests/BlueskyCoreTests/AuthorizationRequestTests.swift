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

    func testFormParametersContainAllRequiredOAuthFields() {
        let pkce = PKCE(codeVerifier: "verifier", codeChallenge: "challenge")
        let request = AuthorizationRequest(
            config: .hoshidukiyo,
            pkce: pkce,
            state: "state-123",
            loginHint: "alice.bsky.social"
        )
        let params = Dictionary(uniqueKeysWithValues: request.formParameters())

        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(params["redirect_uri"], "as.ason:/callback")
        XCTAssertEqual(params["scope"], "atproto transition:generic")
        XCTAssertEqual(params["state"], "state-123")
        XCTAssertEqual(params["code_challenge"], "challenge")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["login_hint"], "alice.bsky.social")
    }

    func testFormParametersOmitLoginHintWhenNil() {
        let pkce = PKCE(codeVerifier: "v", codeChallenge: "c")
        let request = AuthorizationRequest(config: .hoshidukiyo, pkce: pkce, state: "s", loginHint: nil)
        let params = Dictionary(uniqueKeysWithValues: request.formParameters())
        XCTAssertNil(params["login_hint"])
    }

    func testGenerateStateEncodesRandomBytesAsBase64URL() {
        let bytes = Data([0, 0, 0, 0])
        let state = AuthorizationRequest.generateState { count in
            XCTAssertEqual(count, 16)
            return bytes
        }
        XCTAssertEqual(state, Base64URL.encode(bytes))
    }
}
