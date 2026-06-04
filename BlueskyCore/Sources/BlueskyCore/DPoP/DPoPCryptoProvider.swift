import Foundation

/// The cryptographic operations the DPoP layer needs, abstracted from the platform.
/// Apple ships `CryptoKitDPoPProvider`; tests inject a fake. This is the crypto
/// OS-touchpoint from the design (P-256 signing + hashing for DPoP).
public protocol DPoPCryptoProvider: Sendable {
    /// The provider's public key, as embedded in the DPoP proof header `jwk`.
    var publicKeyJWK: ECPublicKeyJWK { get }

    /// Sign `message` with ES256 (ECDSA P-256 + SHA-256). Returns the JOSE raw
    /// signature (64 bytes, r‖s).
    func signES256(_ message: Data) throws -> Data

    /// SHA-256 digest of `data` (used to compute the `ath` claim).
    func sha256(_ data: Data) -> Data
}
