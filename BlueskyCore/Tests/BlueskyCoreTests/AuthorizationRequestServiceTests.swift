import XCTest
@testable import BlueskyCore

final class AuthorizationRequestServiceTests: XCTestCase {
    private func makeService(response: HTTPResponse) -> (AuthorizationRequestService, FakeHTTPClient) {
        let http = FakeHTTPClient(response: response)
        let proofBuilder = DPoPProofBuilder(crypto: FakeDPoPCryptoProvider())
        let sender = DPoPRequestSender(http: http, proofBuilder: proofBuilder)
        return (AuthorizationRequestService(sender: sender), http)
    }

    private func metadata(par: String?) -> AuthorizationServerMetadata {
        let json = ##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"\##(par.map { ",\n          \"pushed_authorization_request_endpoint\": \"\($0)\"" } ?? "")
        }
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
    }

    private func sampleRequest() -> AuthorizationRequest {
        AuthorizationRequest(
            config: .hoshidukiyo,
            pkce: PKCE(codeVerifier: "v", codeChallenge: "c"),
            state: "state-1",
            loginHint: "alice.bsky.social"
        )
    }

    func testPushReturnsRequestURIOnSuccess() async throws {
        let body = Data(##"{"request_uri":"urn:abc","expires_in":60}"##.utf8)
        let (service, http) = makeService(response: HTTPResponse(statusCode: 201, body: body))

        let result = try await service.push(
            metadata: metadata(par: "https://bsky.social/oauth/par"),
            request: sampleRequest()
        )

        XCTAssertEqual(result.requestURI, "urn:abc")
        // Posted to the PAR endpoint as form-urlencoded.
        let sent = http.sentRequests.last
        XCTAssertEqual(sent?.url.absoluteString, "https://bsky.social/oauth/par")
        XCTAssertEqual(sent?.method, .post)
        XCTAssertEqual(
            sent?.headers["Content-Type"],
            "application/x-www-form-urlencoded"
        )
        let sentBody = String(data: sent?.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sentBody.contains("response_type=code"))
        XCTAssertTrue(sentBody.contains("code_challenge=c"))
    }

    func testPushThrowsWhenPAREndpointMissing() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 201))
        do {
            _ = try await service.push(metadata: metadata(par: nil), request: sampleRequest())
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .pushedAuthorizationRequestNotSupported(issuer: "https://bsky.social"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPushThrowsOnNonSuccessStatus() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 400, body: Data("{}".utf8)))
        do {
            _ = try await service.push(
                metadata: metadata(par: "https://bsky.social/oauth/par"),
                request: sampleRequest()
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .authorizationRequestFailed(status: 400))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPushThrowsMalformedDocumentOnUndecodableSuccessBody() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 201, body: Data("not json".utf8)))
        do {
            _ = try await service.push(
                metadata: metadata(par: "https://bsky.social/oauth/par"),
                request: sampleRequest()
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("invalid PAR response"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAuthorizationURLAppendsClientIDAndRequestURI() throws {
        let url = try AuthorizationRequestService.authorizationURL(
            metadata: metadata(par: "https://bsky.social/oauth/par"),
            config: .hoshidukiyo,
            requestURI: "urn:ietf:params:oauth:request_uri:abc"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "bsky.social")
        XCTAssertEqual(components?.path, "/oauth/authorize")
        let items = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(items["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(items["request_uri"], "urn:ietf:params:oauth:request_uri:abc")
    }

    func testAuthorizationURLThrowsOnMalformedEndpoint() {
        let json = ##"{"issuer":"x","authorization_endpoint":"","token_endpoint":"t"}"##
        // swiftlint:disable:next force_try
        let empty = try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
        XCTAssertThrowsError(
            try AuthorizationRequestService.authorizationURL(
                metadata: empty, config: .hoshidukiyo, requestURI: "urn:abc"
            )
        ) { error in
            XCTAssertEqual(error as? OAuthError, .malformedDocument("invalid authorization_endpoint: "))
        }
    }
}
