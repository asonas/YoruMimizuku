import XCTest
@testable import BlueskyCore

final class HTTPClientTests: XCTestCase {
    func test_fakeRecordsRequestAndReturnsStubbedResponse() async throws {
        let url = URL(string: "https://example.com/xrpc/test")!
        let fake = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data("ok".utf8)))

        let response = try await fake.send(HTTPRequest(url: url, method: .get))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "ok")
        XCTAssertEqual(fake.sentRequests.count, 1)
        XCTAssertEqual(fake.sentRequests.first?.url, url)
        XCTAssertEqual(fake.sentRequests.first?.method, .get)
    }
}
