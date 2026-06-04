import Foundation
@testable import BlueskyCore

/// Deterministic `DPoPCryptoProvider` for tests: fixed JWK, fixed signature,
/// and a fixed SHA-256 stand-in. No real crypto, so proof assembly can be
/// asserted byte-for-byte.
struct FakeDPoPCryptoProvider: DPoPCryptoProvider {
    var publicKeyJWK = ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y")
    var signature = Data([0xAA, 0xBB, 0xCC, 0xDD])
    var digest = Data([0x01, 0x02, 0x03, 0x04])

    func signES256(_ message: Data) throws -> Data { signature }
    func sha256(_ data: Data) -> Data { digest }
}
