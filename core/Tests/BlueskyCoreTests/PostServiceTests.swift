import XCTest
@testable import BlueskyCore

final class PostServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private func makeService(http: HTTPClient) -> PostService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return PostService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testUploadBlobPostsBytesWithMimeTypeAndDecodes() async throws {
        let body = Data(##"""
        {"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/jpeg","size":3}}
        """##.utf8)
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: body))
        let service = makeService(http: http)

        let result = try await service.uploadBlob(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            data: Data([0x1, 0x2, 0x3]), mimeType: "image/jpeg"
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.blob.cid, "bafycid")
        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .post)
        XCTAssertTrue(sent.url.absoluteString.hasSuffix("/xrpc/com.atproto.repo.uploadBlob"))
        XCTAssertEqual(sent.headers["Content-Type"], "image/jpeg")
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertEqual(sent.body, Data([0x1, 0x2, 0x3]))
    }
}

extension PostServiceTests {
    func testCreatePostResolvesMentionAndSendsFacets() async throws {
        let profile = HTTPResponse(statusCode: 200, body: Data(##"{"did":"did:plc:alice"}"##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("app.bsky.actor.getProfile") }, response: profile),
            .init(matches: { $0.absoluteString.contains("com.atproto.repo.createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "hi @alice.bsky.social #swift https://x.io",
            images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.response.uri, "at://did:plc:me/app.bsky.feed.post/abc")
        // The createRecord body must carry three facets sorted by byteStart.
        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let body = try XCTUnwrap(createReq.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        let facets = try XCTUnwrap(record["facets"] as? [[String: Any]])
        XCTAssertEqual(facets.count, 3)
        let types = facets.compactMap { ($0["features"] as? [[String: Any]])?.first?["$type"] as? String }
        XCTAssertEqual(types, [
            "app.bsky.richtext.facet#mention",
            "app.bsky.richtext.facet#tag",
            "app.bsky.richtext.facet#link",
        ])
    }

    func testCreatePostDropsMentionWhenResolutionFails() async throws {
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("getProfile") },
                  response: HTTPResponse(statusCode: 400, body: Data(##"{"error":"InvalidRequest"}"##.utf8))),
            .init(matches: { $0.absoluteString.contains("createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "yo @ghost.invalid hello", images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.response.cid, "bafypost")
        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(createReq.body)) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        XCTAssertNil(record["facets"]) // mention dropped, no other facets -> omitted
    }
}
