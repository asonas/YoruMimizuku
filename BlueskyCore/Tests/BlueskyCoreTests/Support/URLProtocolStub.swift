import Foundation

/// Intercepts URLSession traffic so `URLSessionHTTPClient` can be tested offline.
final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var stub: (statusCode: Int, headers: [String: String], body: Data)?
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    static func reset() {
        stub = nil
        capturedRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolStub.capturedRequest = request
        guard let stub = URLProtocolStub.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
