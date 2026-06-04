import Foundation

/// Resolves a handle or DID to a DID, and a DID to its PDS endpoint.
public struct IdentityResolver: Sendable {
    private let http: HTTPClient
    private let directory: URL
    private let plcDirectory: URL

    public init(
        http: HTTPClient,
        directory: URL = URL(string: "https://bsky.social")!,
        plcDirectory: URL = URL(string: "https://plc.directory")!
    ) {
        self.http = http
        self.directory = directory
        self.plcDirectory = plcDirectory
    }

    /// Returns the input unchanged if it is already a DID; otherwise resolves the
    /// handle via `com.atproto.identity.resolveHandle`.
    public func resolveHandleToDID(_ handleOrDID: String) async throws -> String {
        if handleOrDID.hasPrefix("did:") {
            return handleOrDID
        }
        struct ResolveHandleResponse: Decodable { let did: String }
        var components = URLComponents(
            url: directory.appendingPathComponent("xrpc/com.atproto.identity.resolveHandle"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "handle", value: handleOrDID)]
        let response: ResolveHandleResponse = try await getDiscoveryJSON(components.url!, http: http)
        return response.did
    }

    /// Resolves a DID to its PDS endpoint by fetching the DID document. Supports
    /// `did:plc` (via the PLC directory) and `did:web`.
    public func resolveDIDToPDS(_ did: String) async throws -> URL {
        let documentURL: URL
        if did.hasPrefix("did:plc:") {
            documentURL = plcDirectory.appendingPathComponent(did)
        } else if did.hasPrefix("did:web:") {
            let host = String(did.dropFirst("did:web:".count))
            guard let url = URL(string: "https://\(host)/.well-known/did.json") else {
                throw OAuthError.unsupportedDIDMethod(did)
            }
            documentURL = url
        } else {
            throw OAuthError.unsupportedDIDMethod(did)
        }

        let document: DIDDocument = try await getDiscoveryJSON(documentURL, http: http)
        guard let pds = document.pdsEndpoint else {
            throw OAuthError.pdsNotFound(did: did)
        }
        return pds
    }
}
