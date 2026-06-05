import XCTest
import Crypto
@testable import BlueskyCore

final class DPoPProofIntegrationTests: XCTestCase {
    struct DecodedHeader: Decodable {
        let jwk: ECPublicKeyJWK
    }

    func test_realProvider_proofSignatureVerifiesAgainstEmbeddedJWK() throws {
        let provider = CryptoKitDPoPProvider()
        let builder = DPoPProofBuilder(
            crypto: provider,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "integration-jti" }
        )

        let proof = try builder.makeProof(
            method: .post,
            url: URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!,
            accessToken: "an-access-token",
            nonce: "a-nonce"
        )

        let segments = proof.split(separator: ".")
        XCTAssertEqual(segments.count, 3)

        // Reconstruct the public key from the embedded JWK and verify the signature
        // over the signing input (header.claims).
        let headerData = try XCTUnwrap(Base64URL.decode(String(segments[0])))
        let header = try JSONDecoder().decode(DecodedHeader.self, from: headerData)
        let x = try XCTUnwrap(Base64URL.decode(header.jwk.x))
        let y = try XCTUnwrap(Base64URL.decode(header.jwk.y))
        let publicKey = try P256.Signing.PublicKey(rawRepresentation: x + y)

        let signingInput = Data((String(segments[0]) + "." + String(segments[1])).utf8)
        let signatureData = try XCTUnwrap(Base64URL.decode(String(segments[2])))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: signingInput))
    }
}
