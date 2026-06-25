import XCTest
@testable import BlueskyCore

final class VideoUploadServiceTests: XCTestCase {
    private let videoService = VideoServiceConfig(serviceURL: URL(string: "https://video.example")!)
    private let noSleep: @Sendable (Duration) async throws -> Void = { _ in }

    private func inProgress(_ id: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: Data(##"{"jobStatus":{"jobId":"\##(id)","state":"JOB_STATE_ENCODING"}}"##.utf8))
    }
    private func completed(_ id: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: Data(##"""
        {"jobStatus":{"jobId":"\##(id)","state":"JOB_STATE_COMPLETED",
         "blob":{"$type":"blob","ref":{"$link":"bafyvideo"},"mimeType":"video/mp4","size":9}}}
        """##.utf8))
    }
    private func failed(_ id: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: Data(##"{"jobStatus":{"jobId":"\##(id)","state":"JOB_STATE_FAILED","message":"bad"}}"##.utf8))
    }

    // 7. audience(forPDS:) derives did:web:<host>.
    func testAudienceForPDSDerivesDidWeb() {
        let pds = URL(string: "https://morel.us-east.host.bsky.network")!
        XCTAssertEqual(VideoServiceConfig.audience(forPDS: pds), "did:web:morel.us-east.host.bsky.network")
    }

    // 9. uploadVideo POSTs the bytes with Bearer auth and the did/name query.
    func testUploadVideoPostsBytesWithBearerAndQuery() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(##"""
        {"jobId":"job9","did":"did:plc:me","state":"JOB_STATE_CREATED"}
        """##.utf8)))
        let service = VideoUploadService(http: http, config: videoService, sleep: noSleep)

        let status = try await service.uploadVideo(
            serviceToken: "svc.jwt", did: "did:plc:me", name: "clip.mp4",
            data: Data([0xAA, 0xBB]), mimeType: "video/mp4"
        )

        XCTAssertEqual(status.jobId, "job9")
        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .post)
        XCTAssertTrue(sent.url.absoluteString.contains("/xrpc/app.bsky.video.uploadVideo"))
        XCTAssertTrue(sent.url.absoluteString.contains("did=did:plc:me") || sent.url.absoluteString.contains("did=did%3Aplc%3Ame"))
        XCTAssertTrue(sent.url.absoluteString.contains("name=clip.mp4"))
        XCTAssertEqual(sent.headers["Authorization"], "Bearer svc.jwt")
        XCTAssertEqual(sent.headers["Content-Type"], "video/mp4")
        XCTAssertEqual(sent.body, Data([0xAA, 0xBB]))
    }

    // 10. pollUntilComplete returns the blob once the job completes.
    func testPollUntilCompleteReturnsBlob() async throws {
        let http = SequencedHTTPClient([inProgress("j"), inProgress("j"), completed("j")])
        let service = VideoUploadService(http: http, config: videoService, sleep: noSleep)

        let blob = try await service.pollUntilComplete(jobId: "j", serviceToken: "svc", maxAttempts: 5, interval: .seconds(0))

        XCTAssertEqual(blob.cid, "bafyvideo")
        XCTAssertEqual(http.sentRequests.count, 3)
    }

    // 11. pollUntilComplete throws on a failed job.
    func testPollUntilCompleteThrowsOnFailure() async {
        let http = SequencedHTTPClient([inProgress("j"), failed("j")])
        let service = VideoUploadService(http: http, config: videoService, sleep: noSleep)

        do {
            _ = try await service.pollUntilComplete(jobId: "j", serviceToken: "svc", maxAttempts: 5, interval: .seconds(0))
            XCTFail("expected processingFailed")
        } catch let VideoUploadError.processingFailed(state, message) {
            XCTAssertEqual(state, "JOB_STATE_FAILED")
            XCTAssertEqual(message, "bad")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // 12. pollUntilComplete throws timedOut after maxAttempts of in-progress.
    func testPollUntilCompleteTimesOut() async {
        let http = SequencedHTTPClient([inProgress("j"), inProgress("j")])
        let service = VideoUploadService(http: http, config: videoService, sleep: noSleep)

        do {
            _ = try await service.pollUntilComplete(jobId: "j", serviceToken: "svc", maxAttempts: 2, interval: .seconds(0))
            XCTFail("expected timedOut")
        } catch {
            XCTAssertEqual(error as? VideoUploadError, .timedOut)
        }
    }
}

final class GetServiceAuthTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private func makeService(http: HTTPClient) -> PostService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return PostService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    // 8. getServiceAuth builds the aud/lxm/exp query, sends DPoP, returns the token.
    func testGetServiceAuthBuildsQueryAndReturnsToken() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(##"{"token":"svc.jwt"}"##.utf8)))
        let service = makeService(http: http)
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)

        let result = try await service.getServiceAuth(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            audience: "did:web:pds.example", lxm: "com.atproto.repo.uploadBlob",
            expiresInSeconds: 1800, now: fixedNow
        )

        XCTAssertEqual(result.token, "svc.jwt")
        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        let url = sent.url.absoluteString
        XCTAssertTrue(url.contains("/xrpc/com.atproto.server.getServiceAuth"))
        XCTAssertTrue(url.contains("lxm=com.atproto.repo.uploadBlob"))
        XCTAssertTrue(url.contains("exp=1001800"))
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    // createPost with a video blob embeds app.bsky.embed.video and omits images.
    func testCreatePostWithVideoEmbedsVideo() async throws {
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/v","cid":"bafyv"}
        """##.utf8))
        let http = RoutingHTTPClient(routes: [
            .init(matches: { $0.absoluteString.contains("com.atproto.repo.createRecord") }, response: created),
        ])
        let service = makeService(http: http)

        _ = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "見て", images: [], replyParentURI: nil, quote: nil,
            video: (blob: BlobRef(cid: "bafyv", mimeType: "video/mp4", size: 10),
                    aspectRatio: ImageAspectRatio(width: 720, height: 1280), alt: "clip")
        )

        let req = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.body)) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        let embed = try XCTUnwrap(record["embed"] as? [String: Any])
        XCTAssertEqual(embed["$type"] as? String, "app.bsky.embed.video")
        XCTAssertEqual(embed["alt"] as? String, "clip")
        XCTAssertNotNil(embed["video"])
    }
}
