import Foundation

/// An EC P-256 public key in JWK form, as embedded in a DPoP proof header.
public struct ECPublicKeyJWK: Codable, Equatable, Sendable {
    public let kty: String
    public let crv: String
    public let x: String
    public let y: String

    public init(kty: String = "EC", crv: String = "P-256", x: String, y: String) {
        self.kty = kty
        self.crv = crv
        self.x = x
        self.y = y
    }
}
