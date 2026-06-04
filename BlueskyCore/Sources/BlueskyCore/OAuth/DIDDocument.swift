import Foundation

/// The subset of a DID document needed to find an account's PDS.
public struct DIDDocument: Decodable, Equatable, Sendable {
    public struct Service: Decodable, Equatable, Sendable {
        public let id: String
        public let type: String
        public let serviceEndpoint: String
    }

    public let id: String
    public let service: [Service]

    /// The atproto Personal Data Server endpoint, if present.
    public var pdsEndpoint: URL? {
        let match = service.first {
            $0.id.hasSuffix("#atproto_pds") || $0.type == "AtprotoPersonalDataServer"
        }
        return match.flatMap { URL(string: $0.serviceEndpoint) }
    }
}
