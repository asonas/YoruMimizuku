import XCTest
@testable import BlueskyCore

final class XRPCQueryServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private struct Echo: Decodable, Equatable { let value: String }

    private func makeService(http: HTTPClient) -> XRPCQueryService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return XRPCQueryService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testQuerySendsEveryParameterInOrderAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(#"{"value":"ok"}"#.utf8)))
        let service = makeService(http: http)

        let result: (response: Echo, refreshed: TokenResponse?) = try await service.query(
            "app.bsky.feed.getFeedGenerators",
            parameters: [("feeds", "at://a/1"), ("feeds", "at://b/2")],
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk"
        )

        XCTAssertEqual(result.response, Echo(value: "ok"))
        XCTAssertNil(result.refreshed)
        let sent = try XCTUnwrap(http.sentRequests.last)
        let components = try XCTUnwrap(URLComponents(url: sent.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/xrpc/app.bsky.feed.getFeedGenerators")
        XCTAssertEqual(components.queryItems?.map(\.value), ["at://a/1", "at://b/2"])
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testQueryRefreshesOnUnauthorizedAndRetries() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(#"{"error":"invalid_token"}"#.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(#"{"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:alice"}"#.utf8))
        let ok = HTTPResponse(statusCode: 200, body: Data(#"{"value":"ok"}"#.utf8))
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, ok])
        let service = makeService(http: http)

        let result: (response: Echo, refreshed: TokenResponse?) = try await service.query(
            "app.bsky.actor.getPreferences", parameters: [],
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testQueryThrowsRequestFailedWithTheServerError() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 400, body: Data(#"{"error":"UnknownFeed","message":"no such feed"}"#.utf8)))
        let service = makeService(http: http)

        do {
            let _: (response: Echo, refreshed: TokenResponse?) = try await service.query(
                "app.bsky.feed.getFeed", parameters: [("feed", "at://x")],
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil
            )
            XCTFail("expected an error")
        } catch let XRPCError.requestFailed(status, body) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(body?.error, "UnknownFeed")
        }
    }
}
