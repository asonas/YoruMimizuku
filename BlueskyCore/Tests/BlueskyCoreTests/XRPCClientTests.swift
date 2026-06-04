import XCTest
@testable import BlueskyCore

final class XRPCClientTests: XCTestCase {
    struct ResolveHandleResponse: Decodable, Equatable {
        let did: String
    }

    func test_get_buildsXrpcURLWithSortedQueryAndDecodesSuccess() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 200,
                body: Data(#"{"did":"did:plc:abc123"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        let result: ResolveHandleResponse = try await client.get(
            "com.atproto.identity.resolveHandle",
            parameters: ["handle": "asonas.bsky.social"]
        )

        XCTAssertEqual(result, ResolveHandleResponse(did: "did:plc:abc123"))
        XCTAssertEqual(
            fake.sentRequests.first?.url.absoluteString,
            "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social"
        )
        XCTAssertEqual(fake.sentRequests.first?.method, .get)
    }

    struct CreateSessionRequest: Codable {
        let identifier: String
        let password: String
    }

    struct CreateSessionResponse: Decodable, Equatable {
        let accessJwt: String
        let did: String
    }

    func test_post_sendsJSONBodyToXrpcURLAndDecodesResponse() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 200,
                body: Data(#"{"accessJwt":"jwt-token","did":"did:plc:abc123"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        let result: CreateSessionResponse = try await client.post(
            "com.atproto.server.createSession",
            body: CreateSessionRequest(identifier: "asonas.bsky.social", password: "pw")
        )

        XCTAssertEqual(
            result,
            CreateSessionResponse(accessJwt: "jwt-token", did: "did:plc:abc123")
        )

        let sent = try XCTUnwrap(fake.sentRequests.first)
        XCTAssertEqual(
            sent.url.absoluteString,
            "https://bsky.social/xrpc/com.atproto.server.createSession"
        )
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")

        let sentBody = try XCTUnwrap(sent.body)
        let decodedBody = try JSONDecoder().decode(CreateSessionRequest.self, from: sentBody)
        XCTAssertEqual(decodedBody.identifier, "asonas.bsky.social")
        XCTAssertEqual(decodedBody.password, "pw")
    }

    func test_get_throwsRequestFailedOnNon2xxWithDecodedBody() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 400,
                body: Data(#"{"error":"InvalidRequest","message":"bad handle"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        do {
            let _: ResolveHandleResponse = try await client.get(
                "com.atproto.identity.resolveHandle",
                parameters: ["handle": "nope"]
            )
            XCTFail("expected XRPCError.requestFailed")
        } catch let error as XRPCError {
            XCTAssertEqual(
                error,
                .requestFailed(
                    status: 400,
                    body: XRPCErrorResponse(error: "InvalidRequest", message: "bad handle")
                )
            )
        }
    }
}
