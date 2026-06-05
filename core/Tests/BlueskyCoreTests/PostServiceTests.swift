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

extension PostServiceTests {
    func testLikeSendsCreateRecordWithStrongRefSubject() async throws {
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.like/like1","cid":"bafylike"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("com.atproto.repo.createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        let result = try await service.like(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            repo: "did:plc:me",
            subject: StrongRef(uri: "at://did:plc:alice/app.bsky.feed.post/aaa", cid: "bafypost"),
            createdAt: "2026-06-05T00:00:00.000Z"
        )

        XCTAssertEqual(result.response.uri, "at://did:plc:me/app.bsky.feed.like/like1")
        let req = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.headers["Authorization"], "DPoP atk")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.body)) as? [String: Any])
        XCTAssertEqual(json["repo"] as? String, "did:plc:me")
        XCTAssertEqual(json["collection"] as? String, "app.bsky.feed.like")
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        XCTAssertEqual(record["$type"] as? String, "app.bsky.feed.like")
        XCTAssertEqual(record["createdAt"] as? String, "2026-06-05T00:00:00.000Z")
        let subject = try XCTUnwrap(record["subject"] as? [String: Any])
        XCTAssertEqual(subject["uri"] as? String, "at://did:plc:alice/app.bsky.feed.post/aaa")
        XCTAssertEqual(subject["cid"] as? String, "bafypost")
    }

    func testRepostSendsCreateRecordWithRepostCollection() async throws {
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.repost/rp1","cid":"bafyrp"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("com.atproto.repo.createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        let result = try await service.repost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            repo: "did:plc:me",
            subject: StrongRef(uri: "at://did:plc:alice/app.bsky.feed.post/aaa", cid: "bafypost"),
            createdAt: "2026-06-05T00:00:00.000Z"
        )

        XCTAssertEqual(result.response.uri, "at://did:plc:me/app.bsky.feed.repost/rp1")
        let req = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.body)) as? [String: Any])
        XCTAssertEqual(json["collection"] as? String, "app.bsky.feed.repost")
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        XCTAssertEqual(record["$type"] as? String, "app.bsky.feed.repost")
    }

    func testDeleteRecordSendsRepoCollectionRkey() async throws {
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("com.atproto.repo.deleteRecord") },
                  response: HTTPResponse(statusCode: 200, body: Data("{}".utf8))),
        ])
        let service = makeService(http: http)

        let refreshed = try await service.deleteRecord(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            repo: "did:plc:me", collection: "app.bsky.feed.like", rkey: "like1"
        )

        XCTAssertNil(refreshed)
        let req = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(req.method, .post)
        XCTAssertTrue(req.url.absoluteString.hasSuffix("/xrpc/com.atproto.repo.deleteRecord"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.body)) as? [String: Any])
        XCTAssertEqual(json["repo"] as? String, "did:plc:me")
        XCTAssertEqual(json["collection"] as? String, "app.bsky.feed.like")
        XCTAssertEqual(json["rkey"] as? String, "like1")
    }

    func testDeleteRecordRefreshesOnUnauthorized() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token"}
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:me"}
        """##.utf8))
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, HTTPResponse(statusCode: 200, body: Data("{}".utf8))])
        let service = makeService(http: http)

        let refreshed = try await service.deleteRecord(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
            repo: "did:plc:me", collection: "app.bsky.feed.repost", rkey: "rp1"
        )

        XCTAssertEqual(refreshed?.accessToken, "atk2")
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testCreateReplyBuildsRootAndParentFromParentRecord() async throws {
        // Parent is itself a reply, so its reply.root must be reused as the root.
        let getRecord = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:bob/app.bsky.feed.post/parent","cid":"bafyparent",
         "value":{"reply":{"root":{"uri":"at://did:plc:bob/app.bsky.feed.post/root","cid":"bafyroot"}}}}
        """##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/new","cid":"bafynew"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("getRecord") }, response: getRecord),
            .init(matches: { $0.absoluteString.contains("createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        _ = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "thanks", images: [],
            replyParentURI: "at://did:plc:bob/app.bsky.feed.post/parent"
        )

        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(createReq.body)) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        let reply = try XCTUnwrap(record["reply"] as? [String: Any])
        let root = try XCTUnwrap(reply["root"] as? [String: Any])
        let parent = try XCTUnwrap(reply["parent"] as? [String: Any])
        XCTAssertEqual(root["uri"] as? String, "at://did:plc:bob/app.bsky.feed.post/root")
        XCTAssertEqual(parent["uri"] as? String, "at://did:plc:bob/app.bsky.feed.post/parent")
    }

    func testCreatePostRefreshesOnUnauthorizedCreateRecord() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token"}
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:me"}
        """##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, created])
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
            did: "did:plc:me", text: "plain text", images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.cid, "bafypost")
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
}
