import Foundation
import Crypto

/// `DPoPCryptoProvider` backed by swift-crypto's P-256 (CryptoKit on Apple).
///
/// `@unchecked Sendable`: `DPoPCryptoProvider` refines `Sendable`, but
/// swift-crypto does not annotate `P256.Signing.PrivateKey` as `Sendable` on
/// non-Apple platforms (Apple's CryptoKit does). The stored key is an immutable
/// value, so sharing it across concurrency domains is safe.
public struct CryptoKitDPoPProvider: DPoPCryptoProvider, @unchecked Sendable {
    private let privateKey: P256.Signing.PrivateKey

    /// Generate a fresh P-256 key.
    public init() {
        self.privateKey = P256.Signing.PrivateKey()
    }

    /// Wrap an existing key (e.g. one restored from the Keychain in a later plan).
    public init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public var publicKeyJWK: ECPublicKeyJWK {
        // rawRepresentation is the 64-byte uncompressed point (x‖y), no prefix.
        let raw = privateKey.publicKey.rawRepresentation
        let x = raw.prefix(32)
        let y = raw.suffix(32)
        return ECPublicKeyJWK(x: Base64URL.encode(Data(x)), y: Base64URL.encode(Data(y)))
    }

    public func signES256(_ message: Data) throws -> Data {
        // signature(for:) hashes with SHA-256 (ES256) and rawRepresentation is JOSE r‖s.
        try privateKey.signature(for: message).rawRepresentation
    }

    public func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
