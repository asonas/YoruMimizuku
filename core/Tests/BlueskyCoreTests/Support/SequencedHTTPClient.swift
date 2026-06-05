import Foundation
@testable import BlueskyCore

/// Test `HTTPClient` that returns queued responses in order (one per call). Used
/// to drive multi-step flows like the DPoP nonce retry. `@unchecked Sendable`:
/// used serially within async tests.
final class SequencedHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [HTTPResponse]
    private(set) var sentRequests: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        guard !responses.isEmpty else {
            return HTTPResponse(statusCode: 500, body: Data())
        }
        return responses.removeFirst()
    }
}
