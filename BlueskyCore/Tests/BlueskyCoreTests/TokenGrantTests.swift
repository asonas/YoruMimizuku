import XCTest
@testable import BlueskyCore

final class TokenGrantTests: XCTestCase {
    func testAuthorizationCodeGrantParameters() {
        let grant = TokenGrant.authorizationCode(code: "auth-code", codeVerifier: "verifier-1")
        let params = Dictionary(uniqueKeysWithValues: grant.formParameters(config: .yoruMimizuku))

        XCTAssertEqual(params["grant_type"], "authorization_code")
        XCTAssertEqual(params["code"], "auth-code")
        XCTAssertEqual(params["code_verifier"], "verifier-1")
        XCTAssertEqual(params["redirect_uri"], "as.ason:/callback")
        XCTAssertEqual(params["client_id"], "https://ason.as/yorumimizuku/client-metadata.json")
    }

    func testRefreshTokenGrantParameters() {
        let grant = TokenGrant.refresh(refreshToken: "rtk-1")
        let params = Dictionary(uniqueKeysWithValues: grant.formParameters(config: .yoruMimizuku))

        XCTAssertEqual(params["grant_type"], "refresh_token")
        XCTAssertEqual(params["refresh_token"], "rtk-1")
        XCTAssertEqual(params["client_id"], "https://ason.as/yorumimizuku/client-metadata.json")
        // No code/redirect_uri on a refresh.
        XCTAssertNil(params["code"])
        XCTAssertNil(params["redirect_uri"])
    }
}
