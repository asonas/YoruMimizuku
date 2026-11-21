import Foundation

/// The parsed result of an OAuth redirect callback URL.
public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: String?
    /// The authorization server's issuer identifier (RFC 9207), which atproto
    /// servers always send.
    public let issuer: String?

    public init(code: String, state: String?, issuer: String? = nil) {
        self.code = code
        self.state = state
        self.issuer = issuer
    }

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
        return OAuthCallback(code: code, state: values["state"] ?? nil, issuer: values["iss"] ?? nil)
    }

    /// Parse a callback only once it is known to answer the request that was
    /// sent: the same `state`, from the authorization server the login
    /// discovered (RFC 9207). This holds for an error response too, so a denial
    /// from another server is not reported as this server's answer.
    public static func verified(url: URL, expectedState: String, expectedIssuer: String) throws -> OAuthCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Exactly one value, compared code point for code point (Swift's `==`
        // would also accept canonically equivalent strings).
        func single(_ name: String) -> String? {
            let values = items.filter { $0.name == name }
            return values.count == 1 ? values[0].value : nil
        }
        func matches(_ value: String?, _ expected: String) -> Bool {
            value.map { Array($0.utf8) == Array(expected.utf8) } ?? false
        }
        guard matches(single("state"), expectedState) else { throw OAuthError.stateMismatch }
        let issuer = single("iss")
        guard matches(issuer, expectedIssuer) else {
            throw OAuthError.issuerMismatch(expected: expectedIssuer, actual: issuer)
        }
        return try parse(url: url)
    }
}
