import XCTest
@testable import BlueskyCore

final class DPoPCryptoProviderTests: XCTestCase {
    func test_jwk_encodesECP256Fields() throws {
        let jwk = ECPublicKeyJWK(x: "abc", y: "def")
        let json = try JSONEncoder().encode(jwk)
        let object = try JSONSerialization.jsonObject(with: json) as? [String: String]

        XCTAssertEqual(object?["kty"], "EC")
        XCTAssertEqual(object?["crv"], "P-256")
        XCTAssertEqual(object?["x"], "abc")
        XCTAssertEqual(object?["y"], "def")
    }

    func test_fakeProvider_returnsConfiguredValues() throws {
        let fake = FakeDPoPCryptoProvider()
        XCTAssertEqual(fake.publicKeyJWK, ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y"))
        XCTAssertEqual(try fake.signES256(Data("anything".utf8)), Data([0xAA, 0xBB, 0xCC, 0xDD]))
        XCTAssertEqual(fake.sha256(Data("anything".utf8)), Data([0x01, 0x02, 0x03, 0x04]))
    }
}
