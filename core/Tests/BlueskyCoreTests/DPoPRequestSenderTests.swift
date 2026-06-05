import XCTest
@testable import BlueskyCore

final class DPoPRequestSenderTests: XCTestCase {
    private func makeSender(_ http: HTTPClient) -> DPoPRequestSender {
        let builder = DPoPProofBuilder(
            crypto: FakeDPoPCryptoProvider(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "fixed-jti" }
        )
        return DPoPRequestSender(http: http, proofBuilder: builder)
    }

    func test_send_attachesDPoPHeaderAndReturnsResponseWithoutRetry() async throws {
        let http = SequencedHTTPClient([
            HTTPResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!,
            body: Data("x".utf8)
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(http.sentRequests.count, 1)
        XCTAssertNotNil(http.sentRequests.first?.headers["DPoP"], "the request must carry a DPoP proof")
    }

    func test_send_addsAuthorizationHeaderWhenAccessTokenGiven() async throws {
        let http = SequencedHTTPClient([HTTPResponse(statusCode: 200, body: Data("{}".utf8))])
        let sender = makeSender(http)

        _ = try await sender.send(
            method: .get,
            url: URL(string: "https://pds.example.com/xrpc/app.bsky.feed.getTimeline")!,
            accessToken: "access-token-123"
        )

        XCTAssertEqual(http.sentRequests.first?.headers["Authorization"], "DPoP access-token-123")
    }

    struct ProofClaims: Decodable {
        let htm: String
        let htu: String
        let nonce: String?
    }

    private func decodeClaims(fromDPoPHeader proof: String) throws -> ProofClaims {
        let segments = proof.split(separator: ".")
        let payload = try XCTUnwrap(Base64URL.decode(String(segments[1])))
        return try JSONDecoder().decode(ProofClaims.self, from: payload)
    }

    func test_send_retriesOnceWithServerNonce() async throws {
        let challenge = HTTPResponse(
            statusCode: 400,
            headers: ["DPoP-Nonce": "server-nonce-1"],
            body: Data(#"{"error":"use_dpop_nonce"}"#.utf8)
        )
        let success = HTTPResponse(statusCode: 200, body: Data("{}".utf8))
        let http = SequencedHTTPClient([challenge, success])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!,
            body: Data("x".utf8)
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(http.sentRequests.count, 2, "should retry exactly once")

        let firstProof = try XCTUnwrap(http.sentRequests[0].headers["DPoP"])
        let retryProof = try XCTUnwrap(http.sentRequests[1].headers["DPoP"])
        XCTAssertNil(try decodeClaims(fromDPoPHeader: firstProof).nonce)
        XCTAssertEqual(try decodeClaims(fromDPoPHeader: retryProof).nonce, "server-nonce-1")
    }

    func test_send_doesNotRetryWhenNonceChallengeLacksNonceHeader() async throws {
        let challenge = HTTPResponse(
            statusCode: 400,
            body: Data(#"{"error":"use_dpop_nonce"}"#.utf8)
        )
        let http = SequencedHTTPClient([challenge, HTTPResponse(statusCode: 200, body: Data())])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!
        )

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(http.sentRequests.count, 1, "no retry without a nonce to use")
    }
}
