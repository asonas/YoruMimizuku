import Foundation

/// Performs a plain JSON GET via the injected `HTTPClient`, decoding the body or
/// throwing `OAuthError.discoveryFailed` on non-2xx. Used by the discovery layer
/// (well-known docs, DID documents) which are plain GETs rather than XRPC calls.
func getDiscoveryJSON<T: Decodable>(
    _ url: URL,
    http: HTTPClient,
    decoder: JSONDecoder = JSONDecoder()
) async throws -> T {
    let request = HTTPRequest(url: url, method: .get, headers: ["Accept": "application/json"])
    let response = try await http.send(request)
    guard (200..<300).contains(response.statusCode) else {
        throw OAuthError.discoveryFailed(url: url.absoluteString, status: response.statusCode)
    }
    do {
        return try decoder.decode(T.self, from: response.body)
    } catch {
        throw OAuthError.malformedDocument(url.absoluteString)
    }
}
