import XCTest
@testable import BlueskyCore

final class ProfileServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    /// Trimmed `app.bsky.actor.getProfile` response (a profileViewDetailed). Extra
    /// detailed-only keys must be ignored by the `ProfileViewBasic` decoder.
    private static let body = Data(##"""
    {
      "did": "did:plc:me",
      "handle": "me.bsky.social",
      "displayName": "Me",
      "avatar": "https://cdn.example/me.jpg",
      "description": "hello",
      "followersCount": 10,
      "followsCount": 20,
      "postsCount": 30
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> ProfileService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return ProfileService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetProfileSendsAuthorizedGetWithActorAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.body))
        let service = makeService(http: http)

        let result = try await service.getProfile(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk", actor: "did:plc:me"
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.handle, "me.bsky.social")
        XCTAssertEqual(result.response.avatar, "https://cdn.example/me.jpg")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.actor.getProfile"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        XCTAssertEqual(sent.url.query?.contains("actor=did:plc:me"), true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testGetProfileRefreshesOnUnauthorizedAndRetries() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:me"}
        """##.utf8))
        let profile = HTTPResponse(statusCode: 200, body: Self.body)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, profile])
        let service = makeService(http: http)

        let result = try await service.getProfile(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", actor: "did:plc:me"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.handle, "me.bsky.social")
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
}
