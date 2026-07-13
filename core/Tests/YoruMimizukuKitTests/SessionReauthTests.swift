import XCTest
@testable import YoruMimizukuKit

final class SessionReauthTests: XCTestCase {
    func testFirstExpiryProducesRequestForCurrentAccount() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: "alice.bsky.social", isPending: false)
        XCTAssertEqual(req, ReauthRequest(did: "did:plc:alice", handle: "alice.bsky.social"))
    }

    func testExpiryWhileAlreadyPendingIsNoOp() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: "alice.bsky.social", isPending: true)
        XCTAssertNil(req)
    }

    func testExpiryWithNoCurrentAccountIsNoOp() {
        let req = SessionReauth.onExpiry(currentDID: nil, currentHandle: nil, isPending: false)
        XCTAssertNil(req)
    }

    func testNilHandleFallsBackToEmptyString() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: nil, isPending: false)
        XCTAssertEqual(req, ReauthRequest(did: "did:plc:alice", handle: ""))
    }
}
