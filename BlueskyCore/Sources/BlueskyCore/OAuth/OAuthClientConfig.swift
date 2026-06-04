import Foundation

/// Static identity of the OAuth client, mirroring the published
/// `client-metadata.json`. `clientID` is the HTTPS URL of that document.
public struct OAuthClientConfig: Equatable, Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scope: String

    public init(clientID: String, redirectURI: String, scope: String) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scope = scope
    }

    /// Production configuration for Hoshidukiyo. Must stay in sync with
    /// `https://ason.as/hoshidukiyo/client-metadata.json`.
    public static let hoshidukiyo = OAuthClientConfig(
        clientID: "https://ason.as/hoshidukiyo/client-metadata.json",
        redirectURI: "as.ason:/callback",
        scope: "atproto transition:generic"
    )
}
