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

    func test_resolveDIDToPDS_plcFetchesPlcDirectory() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://plc.directory/did:plc:abc123",
                body: ##"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"##
            )
        ])
        let resolver = IdentityResolver(http: http, plcDirectory: URL(string: "https://plc.directory")!)

        let pds = try await resolver.resolveDIDToPDS("did:plc:abc123")

        XCTAssertEqual(pds, URL(string: "https://pds.example.com"))
    }

    func test_resolveDIDToPDS_webFetchesWellKnownDIDJSON() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://example.com/.well-known/did.json",
                body: ##"{"id":"did:web:example.com","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"##
            )
        ])
        let resolver = IdentityResolver(http: http)

        let pds = try await resolver.resolveDIDToPDS("did:web:example.com")

        XCTAssertEqual(pds, URL(string: "https://pds.example.com"))
    }

    func test_resolveDIDToPDS_throwsOnUnsupportedMethod() async {
        let resolver = IdentityResolver(http: RoutingHTTPClient(routes: []))
        do {
            _ = try await resolver.resolveDIDToPDS("did:example:foo")
            XCTFail("expected unsupportedDIDMethod")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .unsupportedDIDMethod("did:example:foo"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_resolveDIDToPDS_throwsWhenNoPDSInDocument() async {
        let http = RoutingHTTPClient.json([
            (url: "https://plc.directory/did:plc:x", body: #"{"id":"did:plc:x","service":[]}"#)
        ])
        let resolver = IdentityResolver(http: http)
        do {
            _ = try await resolver.resolveDIDToPDS("did:plc:x")
            XCTFail("expected pdsNotFound")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .pdsNotFound(did: "did:plc:x"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
