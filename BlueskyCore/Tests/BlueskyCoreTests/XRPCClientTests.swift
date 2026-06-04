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
