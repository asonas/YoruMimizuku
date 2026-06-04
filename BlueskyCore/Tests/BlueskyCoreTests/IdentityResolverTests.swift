import XCTest
@testable import BlueskyCore

final class IdentityResolverTests: XCTestCase {
    func test_resolveHandleToDID_callsResolveHandleAndReturnsDID() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social",
                body: #"{"did":"did:plc:abc123"}"#
            )
        ])
        let resolver = IdentityResolver(http: http, directory: URL(string: "https://bsky.social")!)

        let did = try await resolver.resolveHandleToDID("asonas.bsky.social")

        XCTAssertEqual(did, "did:plc:abc123")
    }

    func test_resolveHandleToDID_returnsInputUnchangedWhenAlreadyDID() async throws {
        let http = RoutingHTTPClient(routes: [])
        let resolver = IdentityResolver(http: http, directory: URL(string: "https://bsky.social")!)

        let did = try await resolver.resolveHandleToDID("did:plc:already")

        XCTAssertEqual(did, "did:plc:already")
        XCTAssertTrue(http.sentRequests.isEmpty, "no network call should be made for a DID input")
    }
}
