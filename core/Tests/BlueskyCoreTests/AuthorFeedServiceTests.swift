import XCTest
@testable import BlueskyCore

final class AuthorFeedServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let feedBody = Data(##"""
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
            "cid": "bafyreialice",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
            "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00.000Z" },
            "indexedAt": "2026-06-04T12:00:01.000Z"
          }
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> AuthorFeedService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return AuthorFeedService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetAuthorFeedSendsActorAndFilterAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.feedBody))
        let service = makeService(http: http)

        let result = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            actor: "did:plc:alice", limit: 50, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(result.response.cursor, "next-page")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.getAuthorFeed"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        let query = sent.url.query ?? ""
        XCTAssertTrue(query.contains("actor=did:plc:alice") || query.contains("actor=did%3Aplc%3Aalice"))
        XCTAssertTrue(query.contains("filter=posts_and_author_threads"))
        XCTAssertTrue(query.contains("limit=50"))
        XCTAssertFalse(query.contains("cursor="))
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testGetAuthorFeedIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.feedBody))
        let service = makeService(http: http)

        _ = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            actor: "did:plc:alice", limit: 20, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=20"), true)
    }

    func testGetAuthorFeedRefreshesOnUnauthorizedAndRetries() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:alice"}
        """##.utf8))
        let feed = HTTPResponse(statusCode: 200, body: Self.feedBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, feed])
        let service = makeService(http: http)

        let result = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", actor: "did:plc:alice"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
}
