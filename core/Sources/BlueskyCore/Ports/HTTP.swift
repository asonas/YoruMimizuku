import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: HTTPMethod, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Abstraction over the platform HTTP stack. Apple ships `URLSessionHTTPClient`;
/// tests inject a fake. This is one of the six OS-touchpoint protocols in the design.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Errors originating from the transport layer itself (below XRPC).
public enum HTTPClientError: Error, Equatable {
    /// The URL loading system returned a response that was not an HTTP response.
    case nonHTTPResponse
}
