import XCTest
@testable import BlueskyCore

final class SearchServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let searchBody = Data(##"""
    {
      "cursor": "next",
      "posts": [
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
          "cid": "bafyreialice",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi #swift", "createdAt": "2026-06-04T12:00:00.000Z" },
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> SearchService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return SearchService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testSearchSendsAuthorizedGetWithQueryAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        let result = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            query: "#swift from:alice.bsky.social", limit: 25, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(result.response.cursor, "next")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.searchPosts"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        // The raw query is percent-encoded into q (the '#' becomes %23).
        XCTAssertEqual(sent.url.query?.contains("q=%23swift%20from:alice.bsky.social"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=25"), true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testSearchIncludesSortWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        _ = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            query: "cats", limit: 25, cursor: nil, sort: "latest"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("sort=latest"), true)
    }

    func testSearchIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        _ = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            query: "cats", limit: 25, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
    }

    func testSearchRefreshesOnUnauthorizedAndRetries() async throws {
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
        let search = HTTPResponse(statusCode: 200, body: Self.searchBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, search])
        let service = makeService(http: http)

        let result = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", query: "cats"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testSearchThrowsOnNonSuccessStatus() async {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 500, body: Data("{}".utf8)))
        let service = makeService(http: http)
        do {
            _ = try await service.searchPosts(
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil, query: "cats"
            )
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 500, body: nil))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
