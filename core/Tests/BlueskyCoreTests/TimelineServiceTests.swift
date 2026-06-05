import XCTest
@testable import BlueskyCore

final class TimelineServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let timelineBody = Data(##"""
    {
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

    private func makeService(http: HTTPClient) -> TimelineService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return TimelineService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetTimelineSendsAuthorizedGetAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.timelineBody))
        let service = makeService(http: http)

        let result = try await service.getTimeline(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk", limit: 50, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(result.response.feed[0].post.author.handle, "alice.bsky.social")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.getTimeline"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        XCTAssertEqual(sent.url.query?.contains("limit=50"), true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertNotNil(sent.headers["DPoP"])
    }

    func testGetTimelineIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.timelineBody))
        let service = makeService(http: http)

        _ = try await service.getTimeline(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil, limit: 20, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=20"), true)
    }

    func testGetTimelineRefreshesOnUnauthorizedAndRetries() async throws {
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
        let timeline = HTTPResponse(statusCode: 200, body: Self.timelineBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, timeline])
        let service = makeService(http: http)

        let result = try await service.getTimeline(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.refreshed?.refreshToken, "rtk2")
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(http.sentRequests.count, 4)
        // The retry used the refreshed access token.
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
        // The token endpoint was hit during refresh.
        XCTAssertTrue(http.sentRequests.contains { $0.url.absoluteString == "https://bsky.social/oauth/token" })
    }

    func testGetTimelineDoesNotRefreshWhenNoRefreshToken() async {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let http = SequencedHTTPClient([unauthorized])
        let service = makeService(http: http)
        do {
            _ = try await service.getTimeline(
                pds: pds, issuer: issuer, accessToken: "old", refreshToken: nil
            )
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 401, body: XRPCErrorResponse(error: "invalid_token", message: nil)))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGetTimelineThrowsOnNonSuccessStatus() async {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 500, body: Data("{}".utf8)))
        let service = makeService(http: http)
        do {
            _ = try await service.getTimeline(
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil
            )
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 500, body: nil))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
