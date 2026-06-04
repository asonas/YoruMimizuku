import XCTest
import CryptoKit
@testable import BlueskyCore

final class CryptoKitDPoPProviderTests: XCTestCase {
    func test_publicKeyJWK_hasP256FieldsWith32ByteCoordinates() throws {
        let provider = CryptoKitDPoPProvider()
        let jwk = provider.publicKeyJWK

        XCTAssertEqual(jwk.kty, "EC")
        XCTAssertEqual(jwk.crv, "P-256")
        XCTAssertEqual(try XCTUnwrap(Base64URL.decode(jwk.x)).count, 32)
        XCTAssertEqual(try XCTUnwrap(Base64URL.decode(jwk.y)).count, 32)
    }

    func test_signES256_producesSignatureThatVerifiesWithPublicKey() throws {
        let key = P256.Signing.PrivateKey()
        let provider = CryptoKitDPoPProvider(privateKey: key)
        let message = Data("message to sign".utf8)

        let rawSignature = try provider.signES256(message)
        XCTAssertEqual(rawSignature.count, 64)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: message))
    }

    func test_sha256_matchesCryptoKit() {
        let provider = CryptoKitDPoPProvider()
        let data = Data("hash me".utf8)

        let expected = Data(SHA256.hash(data: data))
        XCTAssertEqual(provider.sha256(data), expected)
    }
}
