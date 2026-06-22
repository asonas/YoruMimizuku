import XCTest
@testable import BlueskyCore

final class SessionRefresherTests: XCTestCase {
    private let issuer = URL(string: "https://bsky.social")!

    private static let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
    {
      "issuer": "https://bsky.social",
      "authorization_endpoint": "https://bsky.social/oauth/authorize",
      "token_endpoint": "https://bsky.social/oauth/token"
    }
    """##.utf8))

    private func makeRefresher(http: HTTPClient, gate: RefreshGate = RefreshGate()) -> SessionRefresher {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return SessionRefresher(
            sender: sender,
            metadataResolver: OAuthMetadataResolver(http: http),
            config: .yoruMimizuku,
            refreshGate: gate
        )
    }

    func testRefreshReturnsNewTokensAndSendsRefreshGrant() async throws {
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","expires_in":3600,"sub":"did:plc:alice"}
        """##.utf8))
        let http = SequencedHTTPClient([Self.metadata, tokens])
        let refresher = makeRefresher(http: http)

        let result = try await refresher.refresh(issuer: issuer, refreshToken: "rtk")

        XCTAssertEqual(result.accessToken, "atk2")
        XCTAssertEqual(result.refreshToken, "rtk2")
        let tokenReq = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(tokenReq.url.absoluteString, "https://bsky.social/oauth/token")
        let body = String(data: tokenReq.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=refresh_token"), "body: \(body)")
        XCTAssertTrue(body.contains("refresh_token=rtk"), "body: \(body)")
    }

    func testRefreshSurfacesInvalidGrantSoSessionExpiryCanCatchIt() async throws {
        let denied = HTTPResponse(statusCode: 400, body: Data(##"{"error":"invalid_grant"}"##.utf8))
        let http = SequencedHTTPClient([Self.metadata, denied])
        let refresher = makeRefresher(http: http)

        do {
            _ = try await refresher.refresh(issuer: issuer, refreshToken: "dead")
            XCTFail("expected invalid_grant to throw")
        } catch let error as OAuthError {
            guard case .tokenRequestFailed(400, "invalid_grant", _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(SessionExpiry.reportIfExpired(error), "SessionExpiry must recognize this as expired")
        }
    }

    func testConcurrentRefreshesOnSameTokenCoalesceThroughGate() async throws {
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:alice"}
        """##.utf8))
        // Two metadata+token pairs are queued, but a coalesced refresh must consume
        // only the first pair (one token-endpoint call), leaving the rest unused.
        let http = SequencedHTTPClient([Self.metadata, tokens, Self.metadata, tokens])
        let gate = RefreshGate()
        let refresher = makeRefresher(http: http, gate: gate)
        let issuer = self.issuer

        async let a = refresher.refresh(issuer: issuer, refreshToken: "rtk")
        async let b = refresher.refresh(issuer: issuer, refreshToken: "rtk")
        let first = try await a
        let second = try await b

        XCTAssertEqual(first.accessToken, "atk2")
        XCTAssertEqual(second.accessToken, "atk2")
        let tokenCalls = http.sentRequests.filter { $0.url.absoluteString == "https://bsky.social/oauth/token" }
        XCTAssertEqual(tokenCalls.count, 1, "the single-use refresh token must be consumed once")
    }
}
