import Foundation

/// Errors from the OAuth discovery layer.
public enum OAuthError: Error, Equatable {
    case discoveryFailed(url: String, status: Int)
    case malformedDocument(String)
    case pdsNotFound(did: String)
    case unsupportedDIDMethod(String)
    case pushedAuthorizationRequestNotSupported(issuer: String)
    case authorizationRequestFailed(status: Int)
    case tokenRequestFailed(status: Int)
    case authorizationDenied(error: String, description: String?)
    case missingAuthorizationCode
    case stateMismatch
}
