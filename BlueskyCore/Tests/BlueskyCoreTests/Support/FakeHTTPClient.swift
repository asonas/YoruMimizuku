import Foundation
@testable import BlueskyCore

/// Records sent requests and returns a canned response (or throws a canned error).
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    enum Outcome {
        case respond(HTTPResponse)
        case fail(Error)
    }

    var outcome: Outcome
    private(set) var sentRequests: [HTTPRequest] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    convenience init(response: HTTPResponse) {
        self.init(outcome: .respond(response))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        switch outcome {
        case .respond(let response):
            return response
        case .fail(let error):
            throw error
        }
    }
}
