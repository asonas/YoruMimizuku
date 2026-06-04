import Foundation

/// Sends HTTP requests carrying a DPoP proof, transparently handling the
/// `use_dpop_nonce` challenge: if the server rejects the first attempt and supplies
/// a `DPoP-Nonce`, the proof is rebuilt with that nonce and the request is retried
/// exactly once. Used by PAR and token exchange.
public struct DPoPRequestSender: Sendable {
    private let http: HTTPClient
    private let proofBuilder: DPoPProofBuilder

    public init(http: HTTPClient, proofBuilder: DPoPProofBuilder) {
        self.http = http
        self.proofBuilder = proofBuilder
    }

    public func send(
        method: HTTPMethod,
        url: URL,
        accessToken: String? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        let first = try await sendOnce(
            method: method, url: url, accessToken: accessToken,
            nonce: nil, headers: headers, body: body
        )
        guard Self.isNonceChallenge(first), let nonce = Self.dpopNonce(in: first.headers) else {
            return first
        }
        return try await sendOnce(
            method: method, url: url, accessToken: accessToken,
            nonce: nonce, headers: headers, body: body
        )
    }

    private func sendOnce(
        method: HTTPMethod,
        url: URL,
        accessToken: String?,
        nonce: String?,
        headers: [String: String],
        body: Data?
    ) async throws -> HTTPResponse {
        let proof = try proofBuilder.makeProof(
            method: method, url: url, accessToken: accessToken, nonce: nonce
        )
        var merged = headers
        merged["DPoP"] = proof
        if let accessToken {
            merged["Authorization"] = "DPoP \(accessToken)"
        }
        return try await http.send(HTTPRequest(url: url, method: method, headers: merged, body: body))
    }

    /// True when the response is a `use_dpop_nonce` challenge (400/401 whose error body
    /// is `use_dpop_nonce`).
    static func isNonceChallenge(_ response: HTTPResponse) -> Bool {
        guard response.statusCode == 400 || response.statusCode == 401 else { return false }
        guard let error = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body) else {
            return false
        }
        return error.error == "use_dpop_nonce"
    }

    /// Case-insensitive lookup of the `DPoP-Nonce` response header.
    static func dpopNonce(in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare("DPoP-Nonce") == .orderedSame }?.value
    }
}
