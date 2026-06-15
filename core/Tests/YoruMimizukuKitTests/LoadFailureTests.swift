import XCTest
import Foundation
@testable import YoruMimizukuKit
@testable import BlueskyCore

final class LoadFailureTests: XCTestCase {
    func testOfflineURLErrorsClassifyAsOffline() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut]
        for code in codes {
            let failure = LoadFailure(URLError(code))
            XCTAssertEqual(failure.kind, .offline, "expected \(code) to be offline")
        }
    }

    func test429ClassifiesAsRateLimited() {
        let failure = LoadFailure(XRPCError.requestFailed(status: 429, body: nil))
        XCTAssertEqual(failure.kind, .rateLimited)
    }

    func testServerStatusClassifiesAsServer() {
        let failure = LoadFailure(XRPCError.requestFailed(status: 503, body: nil))
        XCTAssertEqual(failure.kind, .server)
    }

    func testOtherErrorsClassifyAsUnknown() {
        XCTAssertEqual(LoadFailure(XRPCError.decodingFailed("x")).kind, .unknown)
        XCTAssertEqual(LoadFailure(XRPCError.requestFailed(status: 404, body: nil)).kind, .unknown)
    }

    func testEachKindHasNonEmptyTitleAndMessage() {
        for error in [URLError(.notConnectedToInternet) as Error,
                      XRPCError.requestFailed(status: 429, body: nil),
                      XRPCError.requestFailed(status: 500, body: nil),
                      XRPCError.decodingFailed("x")] {
            let failure = LoadFailure(error)
            XCTAssertFalse(failure.title.isEmpty)
            XCTAssertFalse(failure.message.isEmpty)
        }
    }

    func testDetailCarriesRawDescription() {
        let failure = LoadFailure(XRPCError.requestFailed(status: 429, body: nil))
        XCTAssertTrue(failure.detail.contains("429"))
    }
}
