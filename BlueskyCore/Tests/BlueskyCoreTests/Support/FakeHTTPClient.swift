import Foundation
@testable import BlueskyCore

/// Records sent requests and returns a canned response (or throws a canned error).
///
/// Test double for `HTTPClient`. Marked `@unchecked Sendable` deliberately: it is used
/// serially within `async` tests (one `send` at a time), so the mutable `sentRequests`
/// and `outcome` are not accessed concurrently. If a future test drives concurrent
/// `send` calls, convert this to an `actor` instead of relying on `@unchecked`.
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
