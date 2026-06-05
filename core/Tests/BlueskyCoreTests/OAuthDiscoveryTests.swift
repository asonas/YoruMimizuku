import XCTest
@testable import BlueskyCore

final class OAuthDiscoveryTests: XCTestCase {
    func test_discover_resolvesHandleToFullAuthorizationServerMetadata() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social",
                body: #"{"did":"did:plc:abc123"}"#
            ),
            (
                url: "https://plc.directory/did:plc:abc123",
                body: ##"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"##
            ),
            (
                url: "https://pds.example.com/.well-known/oauth-protected-resource",
                body: #"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#
            ),
            (
                url: "https://bsky.social/.well-known/oauth-authorization-server",
                body: #"{"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token","pushed_authorization_request_endpoint":"https://bsky.social/oauth/par"}"#
            )
        ])
        let discovery = OAuthDiscovery(http: http)

        let result = try await discovery.discover(account: "asonas.bsky.social")

        XCTAssertEqual(result.did, "did:plc:abc123")
        XCTAssertEqual(result.pds, URL(string: "https://pds.example.com"))
        XCTAssertEqual(result.authorizationServerIssuer, "https://bsky.social")
        XCTAssertEqual(result.metadata.authorizationEndpoint, "https://bsky.social/oauth/authorize")
        XCTAssertEqual(result.metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(result.metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }

    func test_discover_throwsOnIssuerMismatch() async {
        let http = RoutingHTTPClient.json([
            (url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=h", body: #"{"did":"did:plc:abc123"}"#),
            (url: "https://plc.directory/did:plc:abc123", body: ##"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"##),
            (url: "https://pds.example.com/.well-known/oauth-protected-resource", body: #"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#),
            // Metadata claims a DIFFERENT issuer than the URL it was fetched from.
            (url: "https://bsky.social/.well-known/oauth-authorization-server", body: #"{"issuer":"https://evil.example","authorization_endpoint":"https://evil.example/oauth/authorize","token_endpoint":"https://evil.example/oauth/token"}"#)
        ])
        let discovery = OAuthDiscovery(http: http)
        do {
            _ = try await discovery.discover(account: "h")
            XCTFail("expected malformedDocument for issuer mismatch")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("issuer mismatch: expected https://bsky.social, got https://evil.example"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_discover_throwsWhenNoAuthorizationServerListed() async {
        let http = RoutingHTTPClient.json([
            (url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=h", body: #"{"did":"did:plc:abc123"}"#),
            (url: "https://plc.directory/did:plc:abc123", body: ##"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"##),
            (url: "https://pds.example.com/.well-known/oauth-protected-resource", body: #"{"resource":"https://pds.example.com","authorization_servers":[]}"#)
        ])
        let discovery = OAuthDiscovery(http: http)
        do {
            _ = try await discovery.discover(account: "h")
            XCTFail("expected malformedDocument")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("no authorization_servers listed"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
