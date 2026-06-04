import XCTest
@testable import BlueskyCore

final class PKCETests: XCTestCase {
    func test_make_computesChallengeAsBase64URLOfHash() {
        let fixed = Data([0x01, 0x02, 0x03, 0x04])
        let pkce = PKCE.make(verifier: "the-verifier", sha256: { _ in fixed })

        XCTAssertEqual(pkce.codeVerifier, "the-verifier")
        XCTAssertEqual(pkce.codeChallenge, "AQIDBA")
        XCTAssertEqual(pkce.codeChallengeMethod, "S256")
    }

    func test_make_matchesRFC7636TestVectorWithRealSHA256() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let pkce = PKCE.make(verifier: verifier, sha256: CryptoKitDPoPProvider().sha256)

        XCTAssertEqual(pkce.codeChallenge, expectedChallenge)
    }

    func test_generateVerifier_is43CharBase64URLFrom32Bytes() {
        let bytes = Data(repeating: 0xAB, count: 32)
        let verifier = PKCE.generateVerifier(randomBytes: { count in
            XCTAssertEqual(count, 32)
            return bytes
        })

        XCTAssertEqual(verifier.count, 43)
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
    }
}
