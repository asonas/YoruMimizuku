import XCTest
@testable import BlueskyCore

final class DPoPProofBuilderTests: XCTestCase {
    // Decodes the three JWT segments for assertions.
    struct DecodedHeader: Decodable {
        let typ: String
        let alg: String
        let jwk: ECPublicKeyJWK
    }
    struct DecodedClaims: Decodable {
        let htm: String
        let htu: String
        let iat: Int
        let jti: String
        let ath: String?
        let nonce: String?
    }

    func decode<T: Decodable>(_ segment: Substring, as type: T.Type) throws -> T {
        let data = try XCTUnwrap(Base64URL.decode(String(segment)))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func makeBuilder() -> DPoPProofBuilder {
        DPoPProofBuilder(
            crypto: FakeDPoPCryptoProvider(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "fixed-jti" }
        )
    }

    func test_makeProof_buildsHeaderAndBaseClaims_withoutAthOrNonce() throws {
        let builder = makeBuilder()

        let proof = try builder.makeProof(
            method: .get,
            url: URL(string: "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=50")!
        )

        let segments = proof.split(separator: ".")
        XCTAssertEqual(segments.count, 3)

        let header = try decode(segments[0], as: DecodedHeader.self)
        XCTAssertEqual(header.typ, "dpop+jwt")
        XCTAssertEqual(header.alg, "ES256")
        XCTAssertEqual(header.jwk, ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y"))

        let claims = try decode(segments[1], as: DecodedClaims.self)
        XCTAssertEqual(claims.htm, "GET")
        // htu drops the query string.
        XCTAssertEqual(claims.htu, "https://bsky.social/xrpc/app.bsky.feed.getTimeline")
        XCTAssertEqual(claims.iat, 1_700_000_000)
        XCTAssertEqual(claims.jti, "fixed-jti")
        XCTAssertNil(claims.ath)
        XCTAssertNil(claims.nonce)

        // The third segment is base64url(signature bytes from the provider).
        XCTAssertEqual(Base64URL.decode(String(segments[2])), Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }
}
