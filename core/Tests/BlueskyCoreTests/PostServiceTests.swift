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
