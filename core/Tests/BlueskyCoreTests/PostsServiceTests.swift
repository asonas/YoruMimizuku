import XCTest
@testable import BlueskyCore

final class PostsServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let body = Data(##"""
    {
      "posts": [
        {
          "uri": "at://did:plc:me/app.bsky.feed.post/mine",
          "cid": "cidpost",
          "author": { "did": "did:plc:me", "handle": "me.bsky.social", "displayName": "Me" },
          "record": { "$type": "app.bsky.feed.post", "text": "hello world", "createdAt": "2026-06-04T12:00:00.000Z" },
          "replyCount": 0, "repostCount": 1, "likeCount": 2,
          "indexedAt": "2026-06-04T12:00:00.000Z"
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> PostsService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return PostsService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetPostsSendsAuthorizedGetWithUrisAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.body))
        let service = makeService(http: http)

        let result = try await service.getPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            uris: ["at://did:plc:me/app.bsky.feed.post/mine", "at://did:plc:you/app.bsky.feed.post/yours"]
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(result.response.posts[0].record.text, "hello world")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.getPosts"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        let query = sent.url.query ?? ""
        XCTAssertEqual(query.components(separatedBy: "uris=").count - 1, 2, "expected two uris params: \(query)")
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertNotNil(sent.headers["DPoP"])
    }

    func testGetPostsRefreshesOnUnauthorizedAndRetries() async throws {
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
        let posts = HTTPResponse(statusCode: 200, body: Self.body)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, posts])
        let service = makeService(http: http)

        let result = try await service.getPosts(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
            uris: ["at://did:plc:me/app.bsky.feed.post/mine"]
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testGetPostsThrowsOnNonSuccessStatus() async {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 500, body: Data("{}".utf8)))
        let service = makeService(http: http)
        do {
            _ = try await service.getPosts(
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
                uris: ["at://did:plc:me/app.bsky.feed.post/mine"]
            )
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 500, body: nil))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGetPostsWithEmptyUrisReturnsEmptyWithoutRequest() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.body))
        let service = makeService(http: http)

        let result = try await service.getPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil, uris: []
        )

        XCTAssertTrue(result.response.posts.isEmpty)
        XCTAssertTrue(http.sentRequests.isEmpty)
    }
}
