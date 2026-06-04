# OAuth Token Exchange Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** atproto OAuth のトークンエンドポイントに対し、認可コードの交換(`authorization_code`)とリフレッシュ(`refresh_token`)を DPoP 束縛で行い、access/refresh トークンと付随情報(DID `sub`、有効期限、scope)を取得する層を BlueskyCore に追加する。

**Architecture:** Plan 6 で確立したパターンを踏襲する。(1) トークンレスポンスのデコード型 `TokenResponse`、(2) 付与種別を表す `TokenGrant`(`authorization_code` / `refresh_token`)とそのフォームパラメータ生成、(3) `DPoPRequestSender` 経由でトークンエンドポイントに POST し結果をデコードする `TokenService`。ネットワーク往復は既存の `DPoPRequestSender`(nonce 再試行込み)で行い、フォーム本文は既存の `FormURLEncoder` で組み立てる。テストは `FakeHTTPClient` + 実 `DPoPProofBuilder`(fake crypto)を注入する。

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation (`JSONDecoder`)。新規 OS 依存なし。

**Scope note:** ブラウザ認可(`ASWebAuthenticationSession`)、`state` の検証、Keychain 保管、`AccountManager`、OS 乱数実装、アプリ配線は後続のプラットフォームプランに属する。本プランは「トークンエンドポイントとの DPoP 束縛のやり取り」までの純ロジック + サービスに限定する。トークンの保存・更新スケジューリングは扱わない。

---

## File Structure

- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenResponse.swift` — トークンエンドポイント成功レスポンスのデコード型。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenGrant.swift` — 付与種別 enum とフォームパラメータ生成。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenService.swift` — トークンエンドポイントへの DPoP 束縛 POST。
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift` — トークン要求失敗のケースを追加。
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenResponseTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenGrantTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenServiceTests.swift`

**Existing helpers to reuse (do NOT recreate):**
- `OAuthClientConfig` (`OAuth/OAuthClientConfig.swift`): `clientID` / `redirectURI` / `scope`、`.hoshidukiyo`。
- `FormURLEncoder.encode(_:) -> Data` (`OAuth/FormURLEncoder.swift`)。
- `DPoPRequestSender` (`OAuth/DPoPRequestSender.swift`): `init(http:proofBuilder:)`, `send(method:url:accessToken:headers:body:) async throws -> HTTPResponse`。
- `AuthorizationServerMetadata.tokenEndpoint` (`OAuth/OAuthServerMetadata.swift`、非 Optional)。
- `HTTPMethod` / `HTTPResponse` (`Platform/HTTP.swift`)。
- `OAuthError` (`OAuth/OAuthError.swift`)。
- テスト用: `FakeHTTPClient(response:)`(`sentRequests: [HTTPRequest]`)、`FakeDPoPCryptoProvider()`、`DPoPProofBuilder(crypto:)`(`Tests/.../Support/`)。

> 実装着手前に `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift` のシグネチャ(`init(response:)` と `sentRequests.last`)を確認すること。Plan 6 の `AuthorizationRequestServiceTests.swift` が同じ Fake を使う良い参照例。

---

### Task 1: TokenResponse decoding

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenResponse.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenResponseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class TokenResponseTests: XCTestCase {
    func testDecodesFullTokenResponse() throws {
        let json = ##"""
        {
          "access_token": "atk-123",
          "token_type": "DPoP",
          "refresh_token": "rtk-456",
          "expires_in": 3600,
          "scope": "atproto transition:generic",
          "sub": "did:plc:abc123"
        }
        """##
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "atk-123")
        XCTAssertEqual(response.tokenType, "DPoP")
        XCTAssertEqual(response.refreshToken, "rtk-456")
        XCTAssertEqual(response.expiresIn, 3600)
        XCTAssertEqual(response.scope, "atproto transition:generic")
        XCTAssertEqual(response.sub, "did:plc:abc123")
    }

    func testDecodesWhenOptionalFieldsAbsent() throws {
        // refresh_token, expires_in, scope are optional; access_token/token_type/sub required.
        let json = ##"{"access_token":"atk","token_type":"DPoP","sub":"did:plc:x"}"##
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "atk")
        XCTAssertNil(response.refreshToken)
        XCTAssertNil(response.expiresIn)
        XCTAssertNil(response.scope)
        XCTAssertEqual(response.sub, "did:plc:x")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter TokenResponseTests`
Expected: FAIL — `cannot find 'TokenResponse' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Successful response from the OAuth token endpoint (both authorization_code
/// and refresh_token grants). `sub` is the account DID. `tokenType` is "DPoP"
/// for atproto. `refreshToken`/`expiresIn`/`scope` may be omitted by the server.
public struct TokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let scope: String?
    public let sub: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case sub
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter TokenResponseTests`
Expected: PASS (2 cases).

- [ ] **Step 5: Commit**

Use the `/commit` skill (`git ai-commit`). Stage `TokenResponse.swift` + `TokenResponseTests.swift`. Behavioral change. Suggested message: `Add token endpoint response decoding`.

---

### Task 2: TokenGrant + form parameters

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenGrant.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenGrantTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class TokenGrantTests: XCTestCase {
    func testAuthorizationCodeGrantParameters() {
        let grant = TokenGrant.authorizationCode(code: "auth-code", codeVerifier: "verifier-1")
        let params = Dictionary(uniqueKeysWithValues: grant.formParameters(config: .hoshidukiyo))

        XCTAssertEqual(params["grant_type"], "authorization_code")
        XCTAssertEqual(params["code"], "auth-code")
        XCTAssertEqual(params["code_verifier"], "verifier-1")
        XCTAssertEqual(params["redirect_uri"], "as.ason:/callback")
        XCTAssertEqual(params["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
    }

    func testRefreshTokenGrantParameters() {
        let grant = TokenGrant.refresh(refreshToken: "rtk-1")
        let params = Dictionary(uniqueKeysWithValues: grant.formParameters(config: .hoshidukiyo))

        XCTAssertEqual(params["grant_type"], "refresh_token")
        XCTAssertEqual(params["refresh_token"], "rtk-1")
        XCTAssertEqual(params["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
        // No code/redirect_uri on a refresh.
        XCTAssertNil(params["code"])
        XCTAssertNil(params["redirect_uri"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter TokenGrantTests`
Expected: FAIL — `cannot find 'TokenGrant' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// An OAuth token-endpoint grant. `authorization_code` exchanges the code from
/// the browser redirect (with the PKCE verifier); `refresh_token` renews tokens.
/// Both send `client_id` because the client authenticates with method "none".
public enum TokenGrant: Equatable, Sendable {
    case authorizationCode(code: String, codeVerifier: String)
    case refresh(refreshToken: String)

    /// Ordered form parameters for the token request body.
    public func formParameters(config: OAuthClientConfig) -> [(String, String)] {
        switch self {
        case let .authorizationCode(code, codeVerifier):
            return [
                ("grant_type", "authorization_code"),
                ("code", code),
                ("code_verifier", codeVerifier),
                ("redirect_uri", config.redirectURI),
                ("client_id", config.clientID)
            ]
        case let .refresh(refreshToken):
            return [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", config.clientID)
            ]
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter TokenGrantTests`
Expected: PASS (2 cases).

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `TokenGrant.swift` + `TokenGrantTests.swift`. Behavioral change. Suggested message: `Add token grant form parameter building`.

---

### Task 3: TokenService — DPoP-bound token request

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/TokenService.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/TokenServiceTests.swift`

- [ ] **Step 1: Add error case to OAuthError**

Edit `OAuthError.swift` to add one case (keep all existing cases):

```swift
/// Errors from the OAuth discovery layer.
public enum OAuthError: Error, Equatable {
    case discoveryFailed(url: String, status: Int)
    case malformedDocument(String)
    case pdsNotFound(did: String)
    case unsupportedDIDMethod(String)
    case pushedAuthorizationRequestNotSupported(issuer: String)
    case authorizationRequestFailed(status: Int)
    case tokenRequestFailed(status: Int)
}
```

- [ ] **Step 2: Write the failing test**

```swift
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
            config: .hoshidukiyo,
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
                config: .hoshidukiyo,
                grant: .refresh(refreshToken: "rtk")
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .tokenRequestFailed(status: 400))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testExchangeThrowsMalformedDocumentOnUndecodableSuccessBody() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 200, body: Data("not json".utf8)))
        do {
            _ = try await service.requestToken(
                metadata: metadata(),
                config: .hoshidukiyo,
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter TokenServiceTests`
Expected: FAIL — `cannot find 'TokenService' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
import Foundation

/// Performs OAuth token-endpoint requests (authorization_code and refresh_token
/// grants) over a DPoP-bound channel, reusing `DPoPRequestSender`'s built-in
/// `use_dpop_nonce` retry.
public struct TokenService: Sendable {
    private let sender: DPoPRequestSender

    public init(sender: DPoPRequestSender) {
        self.sender = sender
    }

    /// POST the grant to the server's token endpoint. Accepts 200 as success;
    /// any other status throws `tokenRequestFailed`. A 200 with an undecodable
    /// body throws `malformedDocument`, mirroring the discovery/PAR layers.
    public func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse {
        guard let url = URL(string: metadata.tokenEndpoint) else {
            throw OAuthError.malformedDocument("invalid token_endpoint: \(metadata.tokenEndpoint)")
        }
        let body = FormURLEncoder.encode(grant.formParameters(config: config))
        let response = try await sender.send(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        guard response.statusCode == 200 else {
            throw OAuthError.tokenRequestFailed(status: response.statusCode)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: response.body)
        } catch {
            throw OAuthError.malformedDocument("invalid token response")
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter TokenServiceTests`
Expected: PASS (3 cases).

- [ ] **Step 6: Run the full suite**

Run: `swift test --package-path BlueskyCore`
Expected: all tests pass (63 prior + the new ones, 70 total).

- [ ] **Step 7: Commit**

Use the `/commit` skill. Stage `OAuthError.swift` + `TokenService.swift` + `TokenServiceTests.swift`. Behavioral change. Suggested message: `Add DPoP-bound token exchange service`.

---

## Self-Review

- **Spec coverage:** §5.2 step 5(認可コードを DPoP 束縛で交換し access/refresh トークンと DID を取得)は Task 1+3 で実装。§5.3「リフレッシュも DPoP 束縛」は `TokenGrant.refresh` + 同一 `requestToken` 経路で満たす。保管(step 6)とブラウザ認可(step 4)はスコープ外として後続プランへ。
- **Placeholder scan:** TBD/TODO なし。各コードステップは完全。唯一の外部依存である `FakeHTTPClient` の API は冒頭で参照先(Plan 6 のテスト)を明示。
- **Type consistency:** `TokenResponse` / `TokenGrant.formParameters(config:)` / `TokenService.requestToken(metadata:config:grant:)` / `OAuthError.tokenRequestFailed(status:)` を全タスクで同一名で使用。`DPoPRequestSender.send(method:url:accessToken:headers:body:)`、`FormURLEncoder.encode`、`AuthorizationServerMetadata.tokenEndpoint`、`OAuthClientConfig.redirectURI/clientID` は計画時に読んだ既存ソースと一致。`malformedDocument` ラップは Plan 6 の PAR デコード処理と同じ作法。

## Carry-forward to next plans (platform layer)

- ブラウザ認可: `ASWebAuthenticationSession`(custom scheme `as.ason:/callback`)で認可、リダイレクトから `code` と `state` を取り出し `state` を検証 → `TokenGrant.authorizationCode` に渡す。
- OS 乱数 `RandomBytesGenerator`(`PKCE.generateVerifier` / `AuthorizationRequest.generateState` 用)の実装。
- Keychain への per-DID トークン保管 + DPoP 秘密鍵保管、`AccountManager`、トークン期限切れ時の `TokenGrant.refresh` 自動実行。
- discovery → PAR → 認可URL → ブラウザ → token exchange をつなぐ `OAuthClient` ステートマシン。
