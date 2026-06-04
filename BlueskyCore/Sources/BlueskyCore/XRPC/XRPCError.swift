import Foundation

/// The body shape every XRPC endpoint returns on error: `{ "error": ..., "message"?: ... }`.
public struct XRPCErrorResponse: Decodable, Equatable, Sendable {
    public let error: String
    public let message: String?

    public init(error: String, message: String?) {
        self.error = error
        self.message = message
    }
}

/// Errors surfaced by `XRPCClient`.
public enum XRPCError: Error, Equatable {
    /// Non-2xx status. `body` is the decoded error payload when present.
    case requestFailed(status: Int, body: XRPCErrorResponse?)
    /// The success payload could not be decoded into the expected type.
    case decodingFailed(String)
    /// The endpoint NSID could not be turned into a valid URL.
    case invalidURL(String)
}
