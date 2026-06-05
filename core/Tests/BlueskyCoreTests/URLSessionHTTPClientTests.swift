// Relies on URLProtocolStub, which is Apple-only (see URLProtocolStub.swift).
#if canImport(Darwin)
import XCTest
@testable import BlueskyCore

final class URLSessionHTTPClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func test_send_mapsRequestAndResponseThroughURLSession() async throws {
        URLProtocolStub.stub = (
            statusCode: 201,
            headers: ["X-Test": "yes"],
            body: Data("hello".utf8)
        )
        let client = URLSessionHTTPClient(session: makeSession())
        let url = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!

        let response = try await client.send(
            HTTPRequest(
                url: url,
                method: .post,
                headers: ["Content-Type": "application/json"],
                body: Data("{}".utf8)
            )
        )

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.headers["X-Test"], "yes")
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "hello")

        let captured = try XCTUnwrap(URLProtocolStub.capturedRequest)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
#endif
