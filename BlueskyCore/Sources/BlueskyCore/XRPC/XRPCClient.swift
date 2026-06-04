import Foundation

/// Typed GET/POST against `baseURL/xrpc/<nsid>`. Unauthenticated for now;
/// auth headers and DPoP are layered on in a later plan.
public struct XRPCClient: Sendable {
    private let baseURL: URL
    private let http: HTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, http: HTTPClient) {
        self.baseURL = baseURL
        self.http = http
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func get<Response: Decodable>(
        _ nsid: String,
        parameters: [String: String] = [:]
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent("xrpc/\(nsid)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL(nsid)
        }
        if !parameters.isEmpty {
            components.queryItems = parameters
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw XRPCError.invalidURL(nsid)
        }
        let request = HTTPRequest(url: url, method: .get, headers: ["Accept": "application/json"])
        let response = try await http.send(request)
        return try decode(response)
    }

    public func post<Body: Encodable, Response: Decodable>(
        _ nsid: String,
        body: Body
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent("xrpc/\(nsid)")
        let payload = try encoder.encode(body)
        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: payload
        )
        let response = try await http.send(request)
        return try decode(response)
    }

    private func decode<Response: Decodable>(_ response: HTTPResponse) throws -> Response {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? decoder.decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try decoder.decode(Response.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
