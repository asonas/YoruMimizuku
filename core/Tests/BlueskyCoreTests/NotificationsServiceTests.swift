import XCTest
@testable import BlueskyCore

final class NotificationsServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let body = Data(##"""
    {
      "cursor": "next",
      "notifications": [
        {
          "uri": "at://did:plc:bob/app.bsky.feed.like/aaa",
          "cid": "cidlike",
          "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
          "record": { "$type": "app.bsky.feed.like", "createdAt": "2026-06-04T12:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> NotificationsService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return NotificationsService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testListNotificationsSendsAuthorizedGetAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.body))
        let service = makeService(http: http)

        let result = try await service.listNotifications(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk", limit: 50, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.notifications.count, 1)
        XCTAssertEqual(result.response.notifications[0].reason, .like)
        XCTAssertEqual(result.response.cursor, "next")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.notification.listNotifications"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        XCTAssertEqual(sent.url.query?.contains("limit=50"), true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertNotNil(sent.headers["DPoP"])
    }

    func testListNotificationsIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.body))
        let service = makeService(http: http)

        _ = try await service.listNotifications(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil, limit: 20, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=20"), true)
    }

    func testListNotificationsRefreshesOnUnauthorizedAndRetries() async throws {
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
        let notifications = HTTPResponse(statusCode: 200, body: Self.body)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, notifications])
        let service = makeService(http: http)

        let result = try await service.listNotifications(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.notifications.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testListNotificationsThrowsOnNonSuccessStatus() async {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 500, body: Data("{}".utf8)))
        let service = makeService(http: http)
        do {
            _ = try await service.listNotifications(pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil)
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 500, body: nil))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
