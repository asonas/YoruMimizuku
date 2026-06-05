import XCTest
@testable import BlueskyCore

final class ThreadServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!
    private let uri = "at://did:plc:bob/app.bsky.feed.post/reply"

    private static let threadBody = Data(##"""
    {
      "thread": {
        "$type": "app.bsky.feed.defs#threadViewPost",
        "post": {
          "uri": "at://did:plc:bob/app.bsky.feed.post/reply",
          "cid": "bafyreibob",
          "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
          "record": { "text": "返信です", "createdAt": "2026-06-04T12:05:00.000Z" },
          "indexedAt": "2026-06-04T12:05:01.000Z"
        },
        "parent": {
          "$type": "app.bsky.feed.defs#threadViewPost",
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/root",
            "cid": "bafyreialice",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
            "record": { "text": "親", "createdAt": "2026-06-04T12:00:00.000Z" },
            "indexedAt": "2026-06-04T12:00:01.000Z"
          }
        }
      }
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> ThreadService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return ThreadService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetPostThreadSendsAuthorizedGetWithUriAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.threadBody))
        let service = makeService(http: http)

        let result = try await service.getPostThread(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk", uri: uri
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.thread.post.author.handle, "bob.bsky.social")
        XCTAssertEqual(result.response.thread.parentPost?.author.handle, "alice.bsky.social")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.getPostThread"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        XCTAssertTrue(sent.url.query?.contains("uri=") == true)
        XCTAssertTrue(sent.url.query?.contains("parentHeight=80") == true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertNotNil(sent.headers["DPoP"])
    }

    func testGetPostThreadRefreshesOnUnauthorizedAndRetries() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:bob"}
        """##.utf8))
        let thread = HTTPResponse(statusCode: 200, body: Self.threadBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, thread])
        let service = makeService(http: http)

        let result = try await service.getPostThread(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", uri: uri
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.thread.parentPost?.author.handle, "alice.bsky.social")
        XCTAssertEqual(http.sentRequests.count, 4)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
}
