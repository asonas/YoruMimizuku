import XCTest
@testable import BlueskyCore

final class TokenServiceTests: XCTestCase {
    private func makeService(response: HTTPResponse) -> (TokenService, FakeHTTPClient) {
        let http = FakeHTTPClient(response: response)
        let proofBuilder = DPoPProofBuilder(crypto: FakeDPoPCryptoProvider())
        let sender = DPoPRequestSender(http: http, proofBuilder: proofBuilder)
        return (TokenService(sender: sender), http)
    }

    private func metadata() -> AuthorizationServerMetadata {
        let json = ##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
    }

    func testExchangeReturnsTokensOnSuccess() async throws {
        let body = Data(##"""
        {"access_token":"atk","token_type":"DPoP","refresh_token":"rtk","expires_in":3600,"sub":"did:plc:x"}
        """##.utf8)
        let (service, http) = makeService(response: HTTPResponse(statusCode: 200, body: body))

        let result = try await service.requestToken(
            metadata: metadata(),
            config: .yoruMimizuku,
            grant: .authorizationCode(code: "auth-code", codeVerifier: "v")
        )

        XCTAssertEqual(result.accessToken, "atk")
        XCTAssertEqual(result.refreshToken, "rtk")
        XCTAssertEqual(result.sub, "did:plc:x")

        let sent = http.sentRequests.last
        XCTAssertEqual(sent?.url.absoluteString, "https://bsky.social/oauth/token")
        XCTAssertEqual(sent?.method, .post)
        XCTAssertEqual(sent?.headers["Content-Type"], "application/x-www-form-urlencoded")
        let sentBody = String(data: sent?.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sentBody.contains("grant_type=authorization_code"))
        XCTAssertTrue(sentBody.contains("code=auth-code"))
        XCTAssertTrue(sentBody.contains("code_verifier=v"))
    }

    func testExchangeThrowsOnNonSuccessStatus() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 400, body: Data("{}".utf8)))
        do {
            _ = try await service.requestToken(
                metadata: metadata(),
                config: .yoruMimizuku,
                grant: .refresh(refreshToken: "rtk")
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .tokenRequestFailed(status: 400))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRequestTokenThrowsMalformedDocumentOnInvalidTokenEndpoint() async {
        let json = ##"{"issuer":"x","authorization_endpoint":"https://x/a","token_endpoint":""}"##
        // swiftlint:disable:next force_try
        let badMetadata = try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
        let (service, _) = makeService(response: HTTPResponse(statusCode: 200, body: Data("{}".utf8)))
        do {
            _ = try await service.requestToken(
                metadata: badMetadata,
                config: .yoruMimizuku,
                grant: .refresh(refreshToken: "rtk")
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("invalid token_endpoint: "))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testExchangeThrowsMalformedDocumentOnUndecodableSuccessBody() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 200, body: Data("not json".utf8)))
        do {
            _ = try await service.requestToken(
                metadata: metadata(),
                config: .yoruMimizuku,
                grant: .refresh(refreshToken: "rtk")
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("invalid token response"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
