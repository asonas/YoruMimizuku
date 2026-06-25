import Foundation

/// `com.atproto.server.getServiceAuth` response: a short-lived JWT scoped to a
/// service audience and lexicon method. Used to authorize the video upload to the
/// Bluesky video service with a Bearer token.
public struct ServiceAuthResponse: Decodable, Equatable, Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}
