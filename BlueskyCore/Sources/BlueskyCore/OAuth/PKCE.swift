import Foundation

/// PKCE (RFC 7636) parameters for an OAuth authorization. `codeChallenge` is the
/// base64url of SHA-256(`codeVerifier`); the method is always S256 for atproto.
public struct PKCE: Equatable, Sendable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String

    public init(codeVerifier: String, codeChallenge: String, codeChallengeMethod: String = "S256") {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }

    /// Build a PKCE pair from a verifier, hashing with the supplied SHA-256.
    /// In production pass `DPoPCryptoProvider.sha256`; tests pass a fake.
    public static func make(verifier: String, sha256: (Data) -> Data) -> PKCE {
        let challenge = Base64URL.encode(sha256(Data(verifier.utf8)))
        return PKCE(codeVerifier: verifier, codeChallenge: challenge, codeChallengeMethod: "S256")
    }

    /// Generate a code verifier as base64url of 32 random bytes (43 chars, within
    /// the RFC 7636 43–128 length range). `randomBytes` is injected for testability.
    public static func generateVerifier(randomBytes: (Int) -> Data) -> String {
        Base64URL.encode(randomBytes(32))
    }
}
