import Foundation

/// Builds DPoP proof JWTs (RFC 9449). OS-independent: all cryptography is
/// delegated to the injected `DPoPCryptoProvider`.
public struct DPoPProofBuilder: Sendable {
    private let crypto: DPoPCryptoProvider
    private let now: @Sendable () -> Date
    private let makeJTI: @Sendable () -> String

    public init(
        crypto: DPoPCryptoProvider,
        now: @escaping @Sendable () -> Date = { Date() },
        makeJTI: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.crypto = crypto
        self.now = now
        self.makeJTI = makeJTI
    }

    /// Build a compact DPoP proof for the given request. Pass `accessToken` to
    /// include the `ath` claim, and `nonce` when the server demands one.
    public func makeProof(
        method: HTTPMethod,
        url: URL,
        accessToken: String? = nil,
        nonce: String? = nil
    ) throws -> String {
        let header = Header(jwk: crypto.publicKeyJWK)
        let ath = accessToken.map { Base64URL.encode(crypto.sha256(Data($0.utf8))) }
        let claims = Claims(
            htm: method.rawValue,
            htu: Self.htu(from: url),
            iat: Int(now().timeIntervalSince1970),
            jti: makeJTI(),
            ath: ath,
            nonce: nonce
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let headerSegment = Base64URL.encode(try encoder.encode(header))
        let claimsSegment = Base64URL.encode(try encoder.encode(claims))
        let signingInput = headerSegment + "." + claimsSegment
        let signature = try crypto.signES256(Data(signingInput.utf8))
        return signingInput + "." + Base64URL.encode(signature)
    }

    /// The `htu` claim is the request URI with query and fragment removed.
    static func htu(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    private struct Header: Encodable {
        let typ = "dpop+jwt"
        let alg = "ES256"
        let jwk: ECPublicKeyJWK
    }

    private struct Claims: Encodable {
        let htm: String
        let htu: String
        let iat: Int
        let jti: String
        let ath: String?
        let nonce: String?

        enum CodingKeys: String, CodingKey {
            case htm, htu, iat, jti, ath, nonce
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(htm, forKey: .htm)
            try container.encode(htu, forKey: .htu)
            try container.encode(iat, forKey: .iat)
            try container.encode(jti, forKey: .jti)
            try container.encodeIfPresent(ath, forKey: .ath)
            try container.encodeIfPresent(nonce, forKey: .nonce)
        }
    }
}
