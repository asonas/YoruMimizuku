import Foundation

/// Errors from the OAuth discovery layer.
public enum OAuthError: Error, Equatable {
    case discoveryFailed(url: String, status: Int)
    case malformedDocument(String)
    case pdsNotFound(did: String)
    case unsupportedDIDMethod(String)
    case pushedAuthorizationRequestNotSupported(issuer: String)
    case authorizationRequestFailed(status: Int)
    /// A token-endpoint request failed. `error` / `description` carry the OAuth
    /// error body (RFC 6749 `error` / `error_description`) when the server sent
    /// one — `invalid_grant` here means the refresh token is expired/revoked and
    /// the account must sign in again.
    case tokenRequestFailed(status: Int, error: String?, description: String?)
    case authorizationDenied(error: String, description: String?)
    case missingAuthorizationCode
    case stateMismatch
}

extension OAuthError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .discoveryFailed(url, status):
            return "OAuth discovery failed (\(status)): \(url)"
        case let .malformedDocument(detail):
            return "malformed OAuth document: \(detail)"
        case let .pdsNotFound(did):
            return "PDS not found for \(did)"
        case let .unsupportedDIDMethod(method):
            return "unsupported DID method: \(method)"
        case let .pushedAuthorizationRequestNotSupported(issuer):
            return "PAR not supported by \(issuer)"
        case let .authorizationRequestFailed(status):
            return "authorization request failed (\(status))"
        case let .tokenRequestFailed(status, error, description):
            let detail = [error, description].compactMap { $0 }.joined(separator: " — ")
            return detail.isEmpty
                ? "token request failed (\(status))"
                : "token request failed (\(status)): \(detail)"
        case let .authorizationDenied(error, description):
            return "authorization denied: \(error)" + (description.map { " — \($0)" } ?? "")
        case .missingAuthorizationCode:
            return "missing authorization code"
        case .stateMismatch:
            return "OAuth state mismatch"
        }
    }
}
