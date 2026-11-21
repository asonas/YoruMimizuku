import XCTest
@testable import BlueskyCore

final class OAuthClientTests: XCTestCase {
    private func metadata() -> AuthorizationServerMetadata {
        let json = ##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token",
          "pushed_authorization_request_endpoint": "https://bsky.social/oauth/par"
        }
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
    }

    private func discovery() -> OAuthDiscovery.Result {
        OAuthDiscovery.Result(
            did: "did:plc:abc",
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            metadata: metadata()
        )
    }

    private func tokenResponse(sub: String = "did:plc:abc", scope: String? = "atproto transition:generic") -> TokenResponse {
        let scopeField = scope.map { #","scope":"\#($0)""# } ?? ""
        let json = #"{"access_token":"atk","token_type":"DPoP","refresh_token":"rtk","sub":"\#(sub)"\#(scopeField)}"#
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    }

    /// The issuer `discovery()` found, as the authorization server puts it in the redirect.
    private static let encodedIssuer = "https%3A%2F%2Fbsky.social"

    /// The state the deterministic StubRandomBytesGenerator produces (16 bytes of 0xAB).
    private var expectedState: String { Base64URL.encode(Data(repeating: 0xAB, count: 16)) }
    /// The verifier it produces (32 bytes of 0xAB).
    private var expectedVerifier: String { Base64URL.encode(Data(repeating: 0xAB, count: 32)) }

    private func makeClient(
        token: RecordingTokenRequesting,
        browser: StubBrowserAuthorizationSession
    ) -> OAuthClient {
        OAuthClient(
            discovery: FakeAccountDiscovering(result: discovery()),
            authorizationRequester: FakeAuthorizationRequesting(
                response: PushedAuthorizationResponse(requestURI: "urn:req:1", expiresIn: 60)
            ),
            tokenRequester: token,
            browser: browser,
            random: StubRandomBytesGenerator(),
            sha256: { $0 },
            config: .yoruMimizuku
        )
    }

    func testLoginCompletesFullFlow() async throws {
        let token = RecordingTokenRequesting(response: tokenResponse())
        // Realistic browser: the authorization server returns state in the redirect.
        let state = expectedState
        let browser = StubBrowserAuthorizationSession { _, scheme in
            URL(string: "\(scheme):/callback?code=THE_CODE&state=\(state)&iss=\(Self.encodedIssuer)")!
        }
        let client = makeClient(token: token, browser: browser)

        let result = try await client.login(account: "alice.bsky.social")

        // Returned session carries DID, PDS and tokens.
        XCTAssertEqual(result.did, "did:plc:abc")
        XCTAssertEqual(result.pds, URL(string: "https://pds.example")!)
        XCTAssertEqual(result.tokens.accessToken, "atk")
        XCTAssertEqual(result.tokens.refreshToken, "rtk")

        // Browser opened the authorization URL built from the PAR request_uri,
        // using the redirect scheme.
        XCTAssertEqual(browser.openedScheme, "as.ason")
        let opened = URLComponents(url: browser.openedURL!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(opened?.host, "bsky.social")
        XCTAssertEqual(opened?.path, "/oauth/authorize")
        let openedItems = Dictionary(
            uniqueKeysWithValues: (opened?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(openedItems["request_uri"], "urn:req:1")

        // Token exchange used the authorization_code grant with the PKCE verifier
        // and the code from the callback.
        XCTAssertEqual(
            token.lastGrant,
            .authorizationCode(code: "THE_CODE", codeVerifier: expectedVerifier)
        )
    }

    func testLoginThrowsStateMismatchWhenCallbackStateDiffers() async {
        let token = RecordingTokenRequesting(response: tokenResponse())
        let browser = StubBrowserAuthorizationSession { _, scheme in
            URL(string: "\(scheme):/callback?code=THE_CODE&state=WRONG&iss=\(Self.encodedIssuer)")!
        }
        let client = makeClient(token: token, browser: browser)

        do {
            _ = try await client.login(account: "alice.bsky.social")
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .stateMismatch)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // Token exchange must not happen on a state mismatch.
        XCTAssertNil(token.lastGrant)
    }

    // #15: the callback must come from the authorization server the login started
    // with (mix-up defense), and the tokens must be for the account that was
    // resolved, with the atproto scope.
    private func loginError(callbackQuery: String, tokens: TokenResponse? = nil) async -> (OAuthError?, RecordingTokenRequesting) {
        let token = RecordingTokenRequesting(response: tokens ?? tokenResponse())
        let state = expectedState
        let browser = StubBrowserAuthorizationSession { _, scheme in
            URL(string: "\(scheme):/callback?code=THE_CODE&state=\(state)\(callbackQuery)")!
        }
        do {
            _ = try await makeClient(token: token, browser: browser).login(account: "alice.bsky.social")
            return (nil, token)
        } catch {
            return (error as? OAuthError, token)
        }
    }

    func testLoginRejectsACallbackFromAnotherIssuer() async {
        let (error, token) = await loginError(callbackQuery: "&iss=https%3A%2F%2Fevil.example")
        XCTAssertEqual(error, .issuerMismatch(expected: "https://bsky.social", actual: "https://evil.example"))
        XCTAssertNil(token.lastGrant, "no token exchange with an unverified issuer")
    }

    func testLoginRejectsACallbackWithoutIssuer() async {
        let (error, token) = await loginError(callbackQuery: "")
        XCTAssertEqual(error, .issuerMismatch(expected: "https://bsky.social", actual: nil))
        XCTAssertNil(token.lastGrant)
    }

    // RFC 9207: an error response is trusted only from the expected server too.
    func testLoginChecksTheIssuerBeforeReportingADenial() async {
        let (error, _) = await loginError(callbackQuery: "&iss=https%3A%2F%2Fevil.example&error=access_denied")
        XCTAssertEqual(error, .issuerMismatch(expected: "https://bsky.social", actual: "https://evil.example"))
        let (denied, _) = await loginError(callbackQuery: "&iss=\(Self.encodedIssuer)&error=access_denied")
        XCTAssertEqual(denied, .authorizationDenied(error: "access_denied", description: nil))
    }

    // Only one iss and one state may be present; a second could smuggle another value.
    func testLoginRejectsARepeatedIssuer() async {
        let (error, token) = await loginError(callbackQuery: "&iss=\(Self.encodedIssuer)&iss=https%3A%2F%2Fevil.example")
        XCTAssertEqual(error, .issuerMismatch(expected: "https://bsky.social", actual: nil))
        XCTAssertNil(token.lastGrant)
    }

    func testLoginRejectsTokensForAnotherAccount() async {
        let (error, _) = await loginError(
            callbackQuery: "&iss=\(Self.encodedIssuer)", tokens: tokenResponse(sub: "did:plc:someone-else")
        )
        XCTAssertEqual(error, .subjectMismatch(expected: "did:plc:abc", actual: "did:plc:someone-else"))
    }

    func testLoginRejectsTokensWithoutTheAtprotoScope() async {
        let (error, _) = await loginError(callbackQuery: "&iss=\(Self.encodedIssuer)", tokens: tokenResponse(scope: "transition:generic"))
        XCTAssertEqual(error, .missingAtprotoScope)
        let (missing, _) = await loginError(callbackQuery: "&iss=\(Self.encodedIssuer)", tokens: tokenResponse(scope: nil))
        XCTAssertEqual(missing, .missingAtprotoScope)
    }
}
