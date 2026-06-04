# OAuth PAR + Authorization URL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** atproto OAuth の Pushed Authorization Request (PAR) を DPoP 束縛で送信して `request_uri` を受領し、ブラウザに渡す認可 URL を組み立てる層を BlueskyCore に追加する。

**Architecture:** Plan 4(discovery)で得た `AuthorizationServerMetadata` と Plan 5 の `PKCE` / `DPoPRequestSender` を入力に、(1) クライアント設定 `OAuthClientConfig`、(2) `application/x-www-form-urlencoded` エンコーダ、(3) PAR レスポンスのデコード、(4) PAR パラメータ生成、(5) PAR 送信サービス、(6) 認可 URL 構築、を純粋関数と薄いサービスに分けて実装する。ネットワーク往復は既存の `DPoPRequestSender` 経由で行い、テストは `FakeHTTPClient` + 実 `DPoPProofBuilder`(fake crypto) を注入する。

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation (`URLComponents`, `JSONDecoder`)。新規 OS 依存なし。

**Scope note:** ブラウザ認可セッション(`ASWebAuthenticationSession`)、トークン交換、state の OS 乱数実装、Keychain 保管は後続プラン。本プランは「PAR を投げて認可 URL を作る」までの純ロジック + サービスに限定する。`code_challenge_methods_supported` / `dpop_signing_alg_values_supported` のメタデータ拡張は本プランでは不要(YAGNI)のため対象外。

---

## File Structure

- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientConfig.swift` — クライアント識別情報(client_id / redirect_uri / scope)と本番設定。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/FormURLEncoder.swift` — `[(String, String)]` を `application/x-www-form-urlencoded` の `Data` に変換する純関数。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequest.swift` — PAR に送るパラメータ生成 + state 生成 + PAR レスポンス型。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequestService.swift` — PAR 送信(DPoP)と認可 URL 構築。
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift` — PAR 失敗 / PAR 非対応のケースを追加。
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientConfigTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/FormURLEncoderTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestServiceTests.swift`

**Existing helpers to reuse (do NOT recreate):**
- `PKCE` (`OAuth/PKCE.swift`): `codeVerifier` / `codeChallenge` / `codeChallengeMethod`。
- `DPoPRequestSender` (`OAuth/DPoPRequestSender.swift`): `init(http:proofBuilder:)`, `send(method:url:accessToken:headers:body:) async throws -> HTTPResponse`。
- `DPoPProofBuilder` (`DPoP/DPoPProofBuilder.swift`) + `FakeDPoPCryptoProvider` (テスト用、既存)。
- `FakeHTTPClient` (テスト用、既存。`Tests/BlueskyCoreTests/Support/` 配下)。
- `AuthorizationServerMetadata` (`OAuth/OAuthServerMetadata.swift`): `authorizationEndpoint`, `pushedAuthorizationRequestEndpoint` (Optional)。
- `HTTPMethod` / `HTTPResponse` / `HTTPRequest` (`Platform/HTTP.swift`)。
- `Base64URL` (`DPoP/Base64URL.swift`): `encode(_ data: Data) -> String`。

> 実装着手前に、上記テスト用 Fake の正確なシグネチャを `BlueskyCore/Tests/BlueskyCoreTests/Support/` で確認すること(`FakeHTTPClient` が直近リクエストを記録する API 名など)。

---

### Task 1: OAuthClientConfig

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientConfig.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientConfigTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class OAuthClientConfigTests: XCTestCase {
    func testHoshidukiyoProductionConfigMatchesClientMetadata() {
        let config = OAuthClientConfig.hoshidukiyo
        XCTAssertEqual(config.clientID, "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(config.redirectURI, "as.ason:/callback")
        XCTAssertEqual(config.scope, "atproto transition:generic")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter OAuthClientConfigTests`
Expected: FAIL — `cannot find 'OAuthClientConfig' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Static identity of the OAuth client, mirroring the published
/// `client-metadata.json`. `clientID` is the HTTPS URL of that document.
public struct OAuthClientConfig: Equatable, Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scope: String

    public init(clientID: String, redirectURI: String, scope: String) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scope = scope
    }

    /// Production configuration for Hoshidukiyo. Must stay in sync with
    /// `https://ason.as/hoshidukiyo/client-metadata.json`.
    public static let hoshidukiyo = OAuthClientConfig(
        clientID: "https://ason.as/hoshidukiyo/client-metadata.json",
        redirectURI: "as.ason:/callback",
        scope: "atproto transition:generic"
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter OAuthClientConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill (runs `git ai-commit`). Stage `OAuthClientConfig.swift` + `OAuthClientConfigTests.swift`. Behavioral change. Suggested message: `Add OAuth client config with Hoshidukiyo production values`.

---

### Task 2: FormURLEncoder

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/FormURLEncoder.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/FormURLEncoderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class FormURLEncoderTests: XCTestCase {
    func testEncodesPairsAsKeyValueJoinedByAmpersand() {
        let data = FormURLEncoder.encode([("a", "1"), ("b", "2")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "a=1&b=2")
    }

    func testPercentEncodesSpacesAndReservedCharacters() {
        // scope value contains a space; client_id contains ':' and '/'.
        let data = FormURLEncoder.encode([
            ("scope", "atproto transition:generic"),
            ("client_id", "https://ason.as/x")
        ])
        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            "scope=atproto%20transition%3Ageneric&client_id=https%3A%2F%2Fason.as%2Fx"
        )
    }

    func testEmptyInputProducesEmptyData() {
        XCTAssertEqual(FormURLEncoder.encode([]), Data())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter FormURLEncoderTests`
Expected: FAIL — `cannot find 'FormURLEncoder' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Encodes key/value pairs into an `application/x-www-form-urlencoded` body.
/// Spaces and all reserved characters are percent-encoded (space → `%20`),
/// which atproto authorization servers accept for PAR and token requests.
public enum FormURLEncoder {
    /// RFC 3986 unreserved characters: ALPHA / DIGIT / "-" / "." / "_" / "~".
    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    public static func encode(_ pairs: [(String, String)]) -> Data {
        let joined = pairs
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
        return Data(joined.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter FormURLEncoderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `FormURLEncoder.swift` + `FormURLEncoderTests.swift`. Behavioral change. Suggested message: `Add form-urlencoded encoder for OAuth requests`.

---

### Task 3: PushedAuthorizationResponse decoding

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequest.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class AuthorizationRequestTests: XCTestCase {
    func testDecodesPushedAuthorizationResponse() throws {
        let json = ##"{"request_uri":"urn:ietf:params:oauth:request_uri:abc123","expires_in":90}"##
        let response = try JSONDecoder().decode(
            PushedAuthorizationResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.requestURI, "urn:ietf:params:oauth:request_uri:abc123")
        XCTAssertEqual(response.expiresIn, 90)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestTests`
Expected: FAIL — `cannot find 'PushedAuthorizationResponse' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `AuthorizationRequest.swift` with the response type (the request-builder additions come in Task 4 and 5):

```swift
import Foundation

/// Successful PAR response: an opaque `request_uri` the authorization endpoint
/// later resolves, plus its lifetime in seconds.
public struct PushedAuthorizationResponse: Decodable, Equatable, Sendable {
    public let requestURI: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case requestURI = "request_uri"
        case expiresIn = "expires_in"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `AuthorizationRequest.swift` + `AuthorizationRequestTests.swift`. Behavioral change. Suggested message: `Add PAR response decoding`.

---

### Task 4: PAR parameter building + state generation

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequest.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestTests.swift` (add cases)

- [ ] **Step 1: Write the failing test (append to AuthorizationRequestTests)**

```swift
    func testFormParametersContainAllRequiredOAuthFields() {
        let pkce = PKCE(codeVerifier: "verifier", codeChallenge: "challenge")
        let request = AuthorizationRequest(
            config: .hoshidukiyo,
            pkce: pkce,
            state: "state-123",
            loginHint: "alice.bsky.social"
        )
        let params = Dictionary(uniqueKeysWithValues: request.formParameters())

        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(params["redirect_uri"], "as.ason:/callback")
        XCTAssertEqual(params["scope"], "atproto transition:generic")
        XCTAssertEqual(params["state"], "state-123")
        XCTAssertEqual(params["code_challenge"], "challenge")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["login_hint"], "alice.bsky.social")
    }

    func testFormParametersOmitLoginHintWhenNil() {
        let pkce = PKCE(codeVerifier: "v", codeChallenge: "c")
        let request = AuthorizationRequest(config: .hoshidukiyo, pkce: pkce, state: "s", loginHint: nil)
        let params = Dictionary(uniqueKeysWithValues: request.formParameters())
        XCTAssertNil(params["login_hint"])
    }

    func testGenerateStateEncodesRandomBytesAsBase64URL() {
        let bytes = Data([0, 0, 0, 0])
        let state = AuthorizationRequest.generateState { count in
            XCTAssertEqual(count, 16)
            return bytes
        }
        XCTAssertEqual(state, Base64URL.encode(bytes))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestTests`
Expected: FAIL — `cannot find 'AuthorizationRequest' in scope` (the struct does not exist yet; only the response type does).

- [ ] **Step 3: Write minimal implementation (add to AuthorizationRequest.swift)**

```swift
/// The inputs to an OAuth authorization, ready to be serialized as PAR form
/// parameters. `state` is an opaque CSRF token the caller supplies; generate
/// one with `generateState`.
public struct AuthorizationRequest: Equatable, Sendable {
    public let config: OAuthClientConfig
    public let pkce: PKCE
    public let state: String
    public let loginHint: String?

    public init(config: OAuthClientConfig, pkce: PKCE, state: String, loginHint: String? = nil) {
        self.config = config
        self.pkce = pkce
        self.state = state
        self.loginHint = loginHint
    }

    /// Ordered form parameters for the PAR body. `login_hint` is included only
    /// when present.
    public func formParameters() -> [(String, String)] {
        var params: [(String, String)] = [
            ("response_type", "code"),
            ("client_id", config.clientID),
            ("redirect_uri", config.redirectURI),
            ("scope", config.scope),
            ("state", state),
            ("code_challenge", pkce.codeChallenge),
            ("code_challenge_method", pkce.codeChallengeMethod)
        ]
        if let loginHint {
            params.append(("login_hint", loginHint))
        }
        return params
    }

    /// Generate an opaque state value as base64url of 16 random bytes.
    /// `randomBytes` is injected for testability (production passes the OS RNG).
    public static func generateState(randomBytes: (Int) -> Data) -> String {
        Base64URL.encode(randomBytes(16))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestTests`
Expected: PASS (all four cases in this file).

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `AuthorizationRequest.swift` + `AuthorizationRequestTests.swift`. Behavioral change. Suggested message: `Add PAR parameter building and state generation`.

---

### Task 5: AuthorizationRequestService — PAR send (DPoP-bound)

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequestService.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestServiceTests.swift`

- [ ] **Step 1: Add error cases to OAuthError**

Edit `OAuthError.swift` to add two cases:

```swift
/// Errors from the OAuth discovery layer.
public enum OAuthError: Error, Equatable {
    case discoveryFailed(url: String, status: Int)
    case malformedDocument(String)
    case pdsNotFound(did: String)
    case unsupportedDIDMethod(String)
    case pushedAuthorizationRequestNotSupported(issuer: String)
    case authorizationRequestFailed(status: Int)
}
```

- [ ] **Step 2: Write the failing test**

> `FakeHTTPClient` (existing Support helper) is initialized via `init(response:)` and records all sent requests in `sentRequests: [HTTPRequest]` (use `.last`). It returns one canned response, which is sufficient here (no nonce retry exercised). `FakeDPoPCryptoProvider()` and `DPoPProofBuilder(crypto:)` both use defaults — no extra setup.

```swift
import XCTest
@testable import BlueskyCore

final class AuthorizationRequestServiceTests: XCTestCase {
    private func makeService(response: HTTPResponse) -> (AuthorizationRequestService, FakeHTTPClient) {
        let http = FakeHTTPClient(response: response)
        let proofBuilder = DPoPProofBuilder(crypto: FakeDPoPCryptoProvider())
        let sender = DPoPRequestSender(http: http, proofBuilder: proofBuilder)
        return (AuthorizationRequestService(sender: sender), http)
    }

    private func metadata(par: String?) -> AuthorizationServerMetadata {
        let json = ##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"\##(par.map { ",\n          \"pushed_authorization_request_endpoint\": \"\($0)\"" } ?? "")
        }
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
    }

    private func sampleRequest() -> AuthorizationRequest {
        AuthorizationRequest(
            config: .hoshidukiyo,
            pkce: PKCE(codeVerifier: "v", codeChallenge: "c"),
            state: "state-1",
            loginHint: "alice.bsky.social"
        )
    }

    func testPushReturnsRequestURIOnSuccess() async throws {
        let body = Data(##"{"request_uri":"urn:abc","expires_in":60}"##.utf8)
        let (service, http) = makeService(response: HTTPResponse(statusCode: 201, body: body))

        let result = try await service.push(
            metadata: metadata(par: "https://bsky.social/oauth/par"),
            request: sampleRequest()
        )

        XCTAssertEqual(result.requestURI, "urn:abc")
        // Posted to the PAR endpoint as form-urlencoded.
        let sent = http.sentRequests.last
        XCTAssertEqual(sent?.url.absoluteString, "https://bsky.social/oauth/par")
        XCTAssertEqual(sent?.method, .post)
        XCTAssertEqual(
            sent?.headers["Content-Type"],
            "application/x-www-form-urlencoded"
        )
        let sentBody = String(data: sent?.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sentBody.contains("response_type=code"))
        XCTAssertTrue(sentBody.contains("code_challenge=c"))
    }

    func testPushThrowsWhenPAREndpointMissing() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 201))
        do {
            _ = try await service.push(metadata: metadata(par: nil), request: sampleRequest())
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .pushedAuthorizationRequestNotSupported(issuer: "https://bsky.social"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPushThrowsOnNonSuccessStatus() async {
        let (service, _) = makeService(response: HTTPResponse(statusCode: 400, body: Data("{}".utf8)))
        do {
            _ = try await service.push(
                metadata: metadata(par: "https://bsky.social/oauth/par"),
                request: sampleRequest()
            )
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .authorizationRequestFailed(status: 400))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestServiceTests`
Expected: FAIL — `cannot find 'AuthorizationRequestService' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
import Foundation

/// Performs the Pushed Authorization Request (PAR) over a DPoP-bound channel and
/// builds the browser authorization URL from the returned `request_uri`.
public struct AuthorizationRequestService: Sendable {
    private let sender: DPoPRequestSender

    public init(sender: DPoPRequestSender) {
        self.sender = sender
    }

    /// POST the authorization parameters to the server's PAR endpoint.
    /// Accepts 200 or 201 as success; any other status throws.
    public func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse {
        guard let endpoint = metadata.pushedAuthorizationRequestEndpoint,
              let url = URL(string: endpoint) else {
            throw OAuthError.pushedAuthorizationRequestNotSupported(issuer: metadata.issuer)
        }
        let body = FormURLEncoder.encode(request.formParameters())
        let response = try await sender.send(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw OAuthError.authorizationRequestFailed(status: response.statusCode)
        }
        return try JSONDecoder().decode(PushedAuthorizationResponse.self, from: response.body)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestServiceTests`
Expected: PASS (3 cases).

- [ ] **Step 6: Commit**

Use the `/commit` skill. Stage `OAuthError.swift` + `AuthorizationRequestService.swift` + `AuthorizationRequestServiceTests.swift`. Behavioral change. Suggested message: `Add PAR send service with DPoP binding`.

---

### Task 6: Authorization URL construction

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/AuthorizationRequestService.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AuthorizationRequestServiceTests.swift` (add cases)

- [ ] **Step 1: Write the failing test (append to AuthorizationRequestServiceTests)**

```swift
    func testAuthorizationURLAppendsClientIDAndRequestURI() throws {
        let url = try AuthorizationRequestService.authorizationURL(
            metadata: metadata(par: "https://bsky.social/oauth/par"),
            config: .hoshidukiyo,
            requestURI: "urn:ietf:params:oauth:request_uri:abc"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "bsky.social")
        XCTAssertEqual(components?.path, "/oauth/authorize")
        let items = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(items["client_id"], "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(items["request_uri"], "urn:ietf:params:oauth:request_uri:abc")
    }

    func testAuthorizationURLThrowsOnMalformedEndpoint() {
        let bad = metadata(par: nil) // authorization_endpoint is still valid here
        // Force a malformed endpoint by decoding a metadata with an empty endpoint.
        _ = bad
        let json = ##"{"issuer":"x","authorization_endpoint":"","token_endpoint":"t"}"##
        // swiftlint:disable:next force_try
        let empty = try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
        XCTAssertThrowsError(
            try AuthorizationRequestService.authorizationURL(
                metadata: empty, config: .hoshidukiyo, requestURI: "urn:abc"
            )
        )
    }
```

> Note: an empty string is a valid relative URL, so guard against an empty/invalid `authorization_endpoint` explicitly in the implementation (see Step 3). If `URLComponents` accepts the empty host, the `URL(string:)` guard plus an `isEmpty` check below produces the throw.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestServiceTests`
Expected: FAIL — `type 'AuthorizationRequestService' has no member 'authorizationURL'`.

- [ ] **Step 3: Write minimal implementation (add static method to AuthorizationRequestService)**

```swift
    /// Build the browser authorization URL: the server's authorization endpoint
    /// plus `client_id` and the PAR-issued `request_uri`. Per atproto, these are
    /// the only two query parameters needed once PAR has been performed.
    public static func authorizationURL(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        requestURI: String
    ) throws -> URL {
        guard !metadata.authorizationEndpoint.isEmpty,
              var components = URLComponents(string: metadata.authorizationEndpoint),
              components.scheme != nil, components.host != nil else {
            throw OAuthError.malformedDocument(
                "invalid authorization_endpoint: \(metadata.authorizationEndpoint)"
            )
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "request_uri", value: requestURI)
        ]
        guard let url = components.url else {
            throw OAuthError.malformedDocument("could not build authorization URL")
        }
        return url
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AuthorizationRequestServiceTests`
Expected: PASS (all 5 cases in this file).

- [ ] **Step 5: Run the full suite**

Run: `swift test --package-path BlueskyCore`
Expected: all tests pass (49 prior + the new ones).

- [ ] **Step 6: Commit**

Use the `/commit` skill. Stage `AuthorizationRequestService.swift` + `AuthorizationRequestServiceTests.swift`. Behavioral change. Suggested message: `Add authorization URL construction from PAR request_uri`.

---

## Self-Review

- **Spec coverage:** §5.2 step 3 (PAR with PKCE challenge / scope / DPoP proof → `request_uri`) is implemented by Tasks 4–5; the browser-authorize URL (start of §5.2 step 4) is Task 6. Steps 4(actual browser session) / 5(token exchange) / 6(Keychain) remain for later plans, consistent with the scope note. §5.1 client-metadata values are pinned in Task 1.
- **Placeholder scan:** No TBD/TODO; every code step contains complete code. The one external dependency is the test-helper `FakeHTTPClient` API surface, flagged explicitly in Task 5 Step 2 for the implementer to confirm.
- **Type consistency:** `OAuthClientConfig` / `PKCE` (uses existing `codeChallenge` / `codeChallengeMethod`) / `AuthorizationRequest` / `PushedAuthorizationResponse` / `AuthorizationRequestService` names are used identically across tasks. `DPoPRequestSender.send(method:url:accessToken:headers:body:)` and `AuthorizationServerMetadata.pushedAuthorizationRequestEndpoint` match the existing source read during planning. `Base64URL.encode` matches `OAuth/PKCE.swift` usage.

## Carry-forward to next plans

- Browser authorization via `ASWebAuthenticationSession` + custom scheme `as.ason:/callback`, returning the `code` + verifying `state`.
- Token exchange (`authorization_code` grant) over `DPoPRequestSender`, capturing access/refresh tokens and DPoP nonce.
- OS `RandomBytesGenerator` (for `PKCE.generateVerifier` and `AuthorizationRequest.generateState`) lands in the platform plan.
- Consider adding `code_challenge_methods_supported` / `dpop_signing_alg_values_supported` to `AuthorizationServerMetadata` only if a server-capability check becomes necessary.
