import Foundation
@testable import BlueskyCore

/// Test `HTTPClient` that returns a response based on the request URL. Routes are
/// matched in order; the first whose predicate matches wins. Used for multi-step
/// discovery flows where each GET hits a different URL. Marked `@unchecked
/// Sendable`: used serially within async tests.
final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    struct Route {
        let matches: (URL) -> Bool
        let response: HTTPResponse
    }

    private let routes: [Route]
    private(set) var sentRequests: [HTTPRequest] = []

    init(routes: [Route]) {
        self.routes = routes
    }

    /// Convenience: route by exact absolute-string match returning a 200 JSON body.
    static func json(_ pairs: [(url: String, body: String)]) -> RoutingHTTPClient {
        RoutingHTTPClient(routes: pairs.map { pair in
            Route(
                matches: { $0.absoluteString == pair.url },
                response: HTTPResponse(statusCode: 200, body: Data(pair.body.utf8))
            )
        })
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        if let route = routes.first(where: { $0.matches(request.url) }) {
            return route.response
        }
        return HTTPResponse(statusCode: 404, body: Data())
    }
}
