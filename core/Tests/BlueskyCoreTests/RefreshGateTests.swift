import XCTest
@testable import BlueskyCore

final class RefreshGateTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private static func token(access: String, refresh: String) -> TokenResponse {
        let json = ##"""
        {"access_token":"\##(access)","token_type":"DPoP","refresh_token":"\##(refresh)","sub":"did:plc:x"}
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    }

    func testConcurrentRefreshesWithSameTokenRunOnce() async throws {
        let gate = RefreshGate()
        let counter = Counter()
        let perform: @Sendable () async throws -> TokenResponse = {
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(20))
            return Self.token(access: "atk2", refresh: "rtk2")
        }

        async let a = gate.refresh(using: "rtk1", perform: perform)
        async let b = gate.refresh(using: "rtk1", perform: perform)
        let results = try await [a, b]

        let calls = await counter.value
        XCTAssertEqual(calls, 1, "the network refresh must run once for a shared token")
        XCTAssertEqual(results[0].accessToken, "atk2")
        XCTAssertEqual(results[1].accessToken, "atk2")
    }

    func testCachedResultIsReusedForAConsumedToken() async throws {
        let gate = RefreshGate()
        let counter = Counter()
        let perform: @Sendable () async throws -> TokenResponse = {
            await counter.increment()
            return Self.token(access: "atk2", refresh: "rtk2")
        }

        _ = try await gate.refresh(using: "rtk1", perform: perform)
        // A straggler still holding the now-consumed rtk1 must reuse the result
        // rather than replay the consumed token (which would be invalid_grant).
        let again = try await gate.refresh(using: "rtk1") {
            await counter.increment()
            return Self.token(access: "should-not-run", refresh: "x")
        }

        let calls = await counter.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(again.accessToken, "atk2")
    }

    func testDifferentTokensRefreshIndependently() async throws {
        let gate = RefreshGate()
        let counter = Counter()
        _ = try await gate.refresh(using: "rtk1") {
            await counter.increment(); return Self.token(access: "a1", refresh: "r1")
        }
        _ = try await gate.refresh(using: "rtk2") {
            await counter.increment(); return Self.token(access: "a2", refresh: "r2")
        }
        let calls = await counter.value
        XCTAssertEqual(calls, 2)
    }

    func testFailureIsNotCached() async {
        let gate = RefreshGate()
        struct Boom: Error {}
        do {
            _ = try await gate.refresh(using: "rtk1") { throw Boom() }
            XCTFail("expected throw")
        } catch {}
        // A later attempt with the same token must be allowed to run again
        // (a failed refresh is never cached as if it succeeded).
        do {
            let result = try await gate.refresh(using: "rtk1") { Self.token(access: "ok", refresh: "r") }
            XCTAssertEqual(result.accessToken, "ok")
        } catch {
            XCTFail("second attempt should run after a failure: \(error)")
        }
    }
}
