import XCTest
@testable import BlueskyCore

final class XRPCQueryServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private struct Echo: Decodable, Equatable { let value: String }

    private actor RefreshLog {
        private(set) var tokens: [TokenResponse] = []
        func record(_ token: TokenResponse) { tokens.append(token) }
    }

    private let metadataResponse = HTTPResponse(statusCode: 200, body: Data(##"""
    {
      "issuer": "https://bsky.social",
      "authorization_endpoint": "https://bsky.social/oauth/authorize",
      "token_endpoint": "https://bsky.social/oauth/token"
    }
    """##.utf8))
    private let tokensResponse = HTTPResponse(statusCode: 200, body: Data(#"{"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:alice"}"#.utf8))
    private let unauthorized = HTTPResponse(statusCode: 401, body: Data(#"{"error":"invalid_token"}"#.utf8))

    private func makeService(http: HTTPClient) -> XRPCQueryService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return XRPCQueryService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testQuerySendsEveryParameterInOrderAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(#"{"value":"ok"}"#.utf8)))
        let service = makeService(http: http)

        let log = RefreshLog()
        let result: Echo = try await service.query(
            "app.bsky.feed.getFeedGenerators",
            parameters: [("feeds", "at://a/1"), ("feeds", "at://b/2")],
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            onRefresh: { await log.record($0) }
        )

        XCTAssertEqual(result, Echo(value: "ok"))
        let refreshed = await log.tokens
        XCTAssertTrue(refreshed.isEmpty)
        let sent = try XCTUnwrap(http.sentRequests.last)
        let components = try XCTUnwrap(URLComponents(url: sent.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/xrpc/app.bsky.feed.getFeedGenerators")
        XCTAssertEqual(components.queryItems?.map(\.value), ["at://a/1", "at://b/2"])
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    /// Servers read `+` in a query as a space, so a feed cursor such as `a+b`
    /// must go out as `%2B` to come back unchanged.
    func testAPlusInAParameterIsSentEncoded() throws {
        let url = try XRPCQueryService.url(pds: pds, nsid: "app.bsky.feed.getFeed", parameters: [("cursor", "a+b c")])

        XCTAssertEqual(url.query, "cursor=a%2Bb%20c")
    }

    func testQueryRefreshesOnUnauthorizedAndRetries() async throws {
        let ok = HTTPResponse(statusCode: 200, body: Data(#"{"value":"ok"}"#.utf8))
        let http = SequencedHTTPClient([unauthorized, metadataResponse, tokensResponse, ok])
        let service = makeService(http: http)
        let log = RefreshLog()

        let result: Echo = try await service.query(
            "app.bsky.actor.getPreferences", parameters: [],
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
            onRefresh: { await log.record($0) }
        )

        XCTAssertEqual(result, Echo(value: "ok"))
        let refreshed = await log.tokens
        XCTAssertEqual(refreshed.map(\.accessToken), ["atk2"])
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    /// The old refresh token is spent once the refresh succeeds, so the new tokens
    /// must reach the caller even when the retried request then fails.
    func testRefreshedTokensReachTheCallerEvenWhenTheRetryFails() async throws {
        let notFound = HTTPResponse(statusCode: 400, body: Data(#"{"error":"InvalidRequest","message":"List not found"}"#.utf8))
        let http = SequencedHTTPClient([unauthorized, metadataResponse, tokensResponse, notFound])
        let service = makeService(http: http)
        let log = RefreshLog()

        do {
            let _: Echo = try await service.query(
                "app.bsky.graph.getList", parameters: [("list", "at://x")],
                pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
                onRefresh: { await log.record($0) }
            )
            XCTFail("expected the retried request to fail")
        } catch XRPCError.requestFailed(status: 400, _) {}

        let refreshed = await log.tokens
        XCTAssertEqual(refreshed.map(\.accessToken), ["atk2"])
    }

    func testQueryThrowsRequestFailedWithTheServerError() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 400, body: Data(#"{"error":"UnknownFeed","message":"no such feed"}"#.utf8)))
        let service = makeService(http: http)

        do {
            let _: Echo = try await service.query(
                "app.bsky.feed.getFeed", parameters: [("feed", "at://x")],
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
                onRefresh: { _ in }
            )
            XCTFail("expected an error")
        } catch let XRPCError.requestFailed(status, body) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(body?.error, "UnknownFeed")
        }
    }
}
