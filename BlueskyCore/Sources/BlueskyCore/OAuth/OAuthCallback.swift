import Foundation

/// The parsed result of an OAuth redirect callback URL.
public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: String?

    /// Parse a redirect callback URL. Throws `authorizationDenied` if the server
    /// returned an `error`, or `missingAuthorizationCode` if no `code` is present.
    public static func parse(url: URL) throws -> OAuthCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(items.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })

        if let error = values["error"] ?? nil {
            throw OAuthError.authorizationDenied(
                error: error,
                description: values["error_description"] ?? nil
            )
        }
        guard let code = values["code"] ?? nil else {
            throw OAuthError.missingAuthorizationCode
        }
        return OAuthCallback(code: code, state: values["state"] ?? nil)
    }
}
