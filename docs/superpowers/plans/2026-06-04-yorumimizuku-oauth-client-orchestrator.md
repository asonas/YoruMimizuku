# OAuth Client Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** discovery → PKCE/state 生成 → PAR → 認可 URL → ブラウザ認可（抽象）→ コールバック解析 + state 検証 → トークン交換、までを一本につなぐ `OAuthClient` ステートマシンと、それが必要とする OS 乱数生成・ブラウザ認可セッションの抽象、コールバック解析を BlueskyCore に追加する。

**Architecture:** 各ステップ（discovery / PAR / token）は既存の具体型をプロトコル（`AccountDiscovering` / `AuthorizationRequesting` / `TokenRequesting`）で抽象化し、`OAuthClient` はそれらと `BrowserAuthorizationSession` / `RandomBytesGenerator` のみに依存する純粋なオーケストレータにする。これにより、ブラウザも乱数もネットワークもフェイク注入でログイン全体を end-to-end にテストできる。OS 実体（`SecRandomBytesGenerator`）は本プランに含め、ブラウザ実体（`ASWebAuthenticationSession`）と Keychain/AccountManager/アプリ配線は次のプラットフォームプランに回す。

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation (`URLComponents`), Security (`SecRandomCopyBytes`)。

**Scope note:** 本プランは「与えられたブラウザ抽象を使ってログインを完了し、トークンと DID/PDS を返す」までに限定する。トークンの Keychain 保管、DPoP 秘密鍵の永続化、`AccountManager`、トークン自動リフレッシュのスケジューリング、`ASWebAuthenticationSession` 実体、ログイン UI は次プラン。リフレッシュ（`TokenGrant.refresh`）の経路は Plan 7 で実装済みのため再実装しない。

---

## File Structure

- Create: `BlueskyCore/Sources/BlueskyCore/Platform/RandomBytesGenerator.swift` — 乱数抽象プロトコル + Apple 実体 `SecRandomBytesGenerator`。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthCallback.swift` — リダイレクト URL から `code` / `state` を取り出す解析。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/BrowserAuthorizationSession.swift` — ブラウザ認可セッションの抽象プロトコル。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientSteps.swift` — `AccountDiscovering` / `AuthorizationRequesting` / `TokenRequesting` プロトコルと既存具体型の conformance。
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClient.swift` — ログインオーケストレータ + 返り値 `OAuthLoginResult`。
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift` — state 不一致 / 認可拒否 / コード欠落のケースを追加。
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientConfig.swift` — `callbackScheme` 計算プロパティを追加。
- Test: `BlueskyCore/Tests/BlueskyCoreTests/RandomBytesGeneratorTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthCallbackTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientConfigTests.swift`（既存に追記）
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientTests.swift`
- Test support: `BlueskyCore/Tests/BlueskyCoreTests/Support/OAuthClientFakes.swift`（フェイク群）

**Existing helpers to reuse (do NOT recreate):**
- `OAuthDiscovery` (`OAuth/OAuthDiscovery.swift`): `discover(account:) async throws -> OAuthDiscovery.Result`、`Result { did, pds, authorizationServerIssuer, metadata }`。
- `AuthorizationRequestService` (`OAuth/AuthorizationRequestService.swift`): `push(metadata:request:) async throws -> PushedAuthorizationResponse`、`static authorizationURL(metadata:config:requestURI:) throws -> URL`。
- `TokenService` (`OAuth/TokenService.swift`): `requestToken(metadata:config:grant:) async throws -> TokenResponse`。
- `PKCE` (`OAuth/PKCE.swift`): `generateVerifier(randomBytes:)`、`make(verifier:sha256:)`、`codeVerifier`。
- `AuthorizationRequest` (`OAuth/AuthorizationRequest.swift`): `init(config:pkce:state:loginHint:)`、`generateState(randomBytes:)`。
- `OAuthClientConfig` (`.yoruMimizuku`, `clientID`, `redirectURI`, `scope`)、`TokenGrant.authorizationCode`、`TokenResponse`、`Base64URL.encode`。
- テスト用: 既存 Support の `FakeHTTPClient` / `FakeDPoPCryptoProvider` は本プランでは不要（新フェイクを `OAuthClientFakes.swift` に置く）。

---

### Task 1: RandomBytesGenerator protocol + Apple implementation

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/RandomBytesGenerator.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/RandomBytesGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class RandomBytesGeneratorTests: XCTestCase {
    func testSecGeneratorReturnsRequestedLength() {
        let generator = SecRandomBytesGenerator()
        XCTAssertEqual(generator.bytes(16).count, 16)
        XCTAssertEqual(generator.bytes(32).count, 32)
        XCTAssertEqual(generator.bytes(0).count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter RandomBytesGeneratorTests`
Expected: FAIL — `cannot find 'SecRandomBytesGenerator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import Security

/// Source of cryptographically secure random bytes. Injected into PKCE verifier
/// and OAuth state generation so tests can supply deterministic bytes. One of
/// the OS-touchpoint abstractions in the design.
public protocol RandomBytesGenerator: Sendable {
    func bytes(_ count: Int) -> Data
}

/// Apple implementation backed by `SecRandomCopyBytes`. Falls back to an empty
/// buffer only if the OS RNG fails, which in practice does not happen on Apple
/// platforms.
public struct SecRandomBytesGenerator: RandomBytesGenerator {
    public init() {}

    public func bytes(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        guard status == errSecSuccess else { return Data() }
        return Data(buffer)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter RandomBytesGeneratorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill (`git ai-commit`). Stage `RandomBytesGenerator.swift` + `RandomBytesGeneratorTests.swift`. Behavioral change. Suggested message: `Add random bytes generator abstraction with Apple implementation`.

---

### Task 2: OAuthClientConfig.callbackScheme

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientConfig.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientConfigTests.swift` (add a case)

- [ ] **Step 1: Write the failing test (append to OAuthClientConfigTests)**

```swift
    func testCallbackSchemeIsTheRedirectURIScheme() {
        XCTAssertEqual(OAuthClientConfig.yoruMimizuku.callbackScheme, "as.ason")
        let custom = OAuthClientConfig(clientID: "x", redirectURI: "myapp:/cb", scope: "s")
        XCTAssertEqual(custom.callbackScheme, "myapp")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter OAuthClientConfigTests`
Expected: FAIL — `value of type 'OAuthClientConfig' has no member 'callbackScheme'`.

- [ ] **Step 3: Write minimal implementation (add computed property inside OAuthClientConfig)**

```swift
    /// The custom URL scheme used for the OAuth redirect (the part of
    /// `redirectURI` before the first colon). `ASWebAuthenticationSession`
    /// needs this scheme to detect the callback.
    public var callbackScheme: String {
        guard let colon = redirectURI.firstIndex(of: ":") else { return redirectURI }
        return String(redirectURI[..<colon])
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter OAuthClientConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `OAuthClientConfig.swift` + `OAuthClientConfigTests.swift`. Behavioral change. Suggested message: `Add callback scheme derivation to OAuth client config`.

---

### Task 3: OAuth callback parsing + error cases

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthCallback.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthCallbackTests.swift`

- [ ] **Step 1: Add error cases to OAuthError**

Edit `OAuthError.swift`, keeping all existing cases and adding three:

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
    case authorizationDenied(error: String, description: String?)
    case missingAuthorizationCode
    case stateMismatch
}
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class OAuthCallbackTests: XCTestCase {
    func testParsesCodeAndState() throws {
        let url = URL(string: "as.ason:/callback?code=auth-code&state=st-1")!
        let callback = try OAuthCallback.parse(url: url)
        XCTAssertEqual(callback.code, "auth-code")
        XCTAssertEqual(callback.state, "st-1")
    }

    func testThrowsAuthorizationDeniedWhenErrorPresent() {
        let url = URL(string: "as.ason:/callback?error=access_denied&error_description=nope")!
        XCTAssertThrowsError(try OAuthCallback.parse(url: url)) { error in
            XCTAssertEqual(
                error as? OAuthError,
                .authorizationDenied(error: "access_denied", description: "nope")
            )
        }
    }

    func testThrowsMissingCodeWhenCodeAbsent() {
        let url = URL(string: "as.ason:/callback?state=st-1")!
        XCTAssertThrowsError(try OAuthCallback.parse(url: url)) { error in
            XCTAssertEqual(error as? OAuthError, .missingAuthorizationCode)
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter OAuthCallbackTests`
Expected: FAIL — `cannot find 'OAuthCallback' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
import Foundation

/// The parsed result of an OAuth redirect callback URL.
public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: String?

    /// Parse a redirect callback URL. Throws `authorizationDenied` if the server
    /// returned an `error`, or `missingAuthorizationCode` if no `code` is present.
    public static func parse(url: URL) throws -> OAuthCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(items.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })

        if let error = values["error"] ?? nil {
            throw OAuthError.authorizationDenied(
                error: error,
                description: values["error_description"] ?? nil
            )
        }
        guard let code = values["code"] ?? nil else {
            throw OAuthError.missingAuthorizationCode
        }
        return OAuthCallback(code: code, state: values["state"] ?? nil)
    }
}
```

> Note: `URLQueryItem.value` is `String?`, so the dictionary values are `String?`; the `?? nil` flattens the double-optional from the subscript. Keep it as written.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter OAuthCallbackTests`
Expected: PASS (3 cases).

- [ ] **Step 6: Commit**

Use the `/commit` skill. Stage `OAuthError.swift` + `OAuthCallback.swift` + `OAuthCallbackTests.swift`. Behavioral change. Suggested message: `Add OAuth callback URL parsing`.

---

### Task 4: BrowserAuthorizationSession protocol

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/BrowserAuthorizationSession.swift`

(No standalone test: this is a pure protocol declaration, exercised end-to-end in Task 6 via a fake. Adding a test that only asserts a fake conforms would be a testing-of-mocks anti-pattern.)

- [ ] **Step 1: Write the protocol**

```swift
import Foundation

/// Opens an authorization URL in a system browser session and resolves with the
/// redirect callback URL once the user approves. On Apple platforms this is
/// implemented with `ASWebAuthenticationSession`; tests inject a fake. One of the
/// OS-touchpoint abstractions in the design.
public protocol BrowserAuthorizationSession: Sendable {
    /// Present `url`, wait for a redirect whose scheme equals `callbackScheme`,
    /// and return the full callback URL. Throws if the user cancels or the
    /// session fails.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path BlueskyCore`
Expected: Build succeeds (no test yet).

- [ ] **Step 3: Commit**

Use the `/commit` skill. Stage `BrowserAuthorizationSession.swift`. Behavioral change. Suggested message: `Add browser authorization session protocol`.

---

### Task 5: Step protocols + conformances

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClientSteps.swift`
- Test: covered indirectly in Task 6; add no separate test here (conformance-only).

- [ ] **Step 1: Write the protocols and conformances**

```swift
import Foundation

/// Resolves an account handle/DID to the endpoints needed to start OAuth.
/// Conformed by `OAuthDiscovery`; faked in tests.
public protocol AccountDiscovering: Sendable {
    func discover(account: String) async throws -> OAuthDiscovery.Result
}

/// Performs the Pushed Authorization Request. Conformed by
/// `AuthorizationRequestService`; faked in tests.
public protocol AuthorizationRequesting: Sendable {
    func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse
}

/// Performs a token-endpoint request. Conformed by `TokenService`; faked in tests.
public protocol TokenRequesting: Sendable {
    func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse
}

extension OAuthDiscovery: AccountDiscovering {}
extension AuthorizationRequestService: AuthorizationRequesting {}
extension TokenService: TokenRequesting {}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path BlueskyCore`
Expected: Build succeeds. (The extensions are empty because the existing method signatures already match the protocol requirements: `OAuthDiscovery.discover(account:)`, `AuthorizationRequestService.push(metadata:request:)`, `TokenService.requestToken(metadata:config:grant:)`.)

> If any conformance fails to compile, the existing method signature differs from the protocol — adjust the PROTOCOL to match the existing concrete method exactly (do not change the concrete types). Re-read the concrete method signatures in the corresponding source files.

- [ ] **Step 3: Commit**

Use the `/commit` skill. Stage `OAuthClientSteps.swift`. Structural change (introduces seams without altering behavior). Suggested message: `Add OAuth step protocols for orchestrator dependency injection`.

---

### Task 6: OAuthClient login orchestrator

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthClient.swift`
- Test support: `BlueskyCore/Tests/BlueskyCoreTests/Support/OAuthClientFakes.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/OAuthClientTests.swift`

- [ ] **Step 1: Write the test fakes (Support file)**

```swift
import Foundation
@testable import BlueskyCore

/// Deterministic random source: every byte is 0xAB, so derived verifier/state
/// are reproducible in tests.
struct StubRandomBytesGenerator: RandomBytesGenerator {
    func bytes(_ count: Int) -> Data { Data(repeating: 0xAB, count: count) }
}

struct FakeAccountDiscovering: AccountDiscovering {
    let result: OAuthDiscovery.Result
    func discover(account: String) async throws -> OAuthDiscovery.Result { result }
}

struct FakeAuthorizationRequesting: AuthorizationRequesting {
    let response: PushedAuthorizationResponse
    func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse { response }
}

/// Records the grant it was asked to exchange, then returns a canned response.
final class RecordingTokenRequesting: TokenRequesting, @unchecked Sendable {
    let response: TokenResponse
    private(set) var lastGrant: TokenGrant?
    init(response: TokenResponse) { self.response = response }
    func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse {
        lastGrant = grant
        return response
    }
}

/// Echoes back a callback URL built from a supplied builder that receives the
/// authorization URL the client tried to open.
final class StubBrowserAuthorizationSession: BrowserAuthorizationSession, @unchecked Sendable {
    let makeCallback: (URL, String) -> URL
    private(set) var openedURL: URL?
    private(set) var openedScheme: String?
    init(makeCallback: @escaping (URL, String) -> URL) { self.makeCallback = makeCallback }
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURL = url
        openedScheme = callbackScheme
        return makeCallback(url, callbackScheme)
    }
}
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class OAuthClientTests: XCTestCase {
    private func metadata() -> AuthorizationServerMetadata {
        let json = ##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token",
          "pushed_authorization_request_endpoint": "https://bsky.social/oauth/par"
        }
        """##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(json.utf8))
    }

    private func discovery() -> OAuthDiscovery.Result {
        OAuthDiscovery.Result(
            did: "did:plc:abc",
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            metadata: metadata()
        )
    }

    private func tokenResponse() -> TokenResponse {
        let json = ##"{"access_token":"atk","token_type":"DPoP","refresh_token":"rtk","sub":"did:plc:abc"}"##
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    }

    /// The state the deterministic StubRandomBytesGenerator produces (16 bytes of 0xAB).
    private var expectedState: String { Base64URL.encode(Data(repeating: 0xAB, count: 16)) }
    /// The verifier it produces (32 bytes of 0xAB).
    private var expectedVerifier: String { Base64URL.encode(Data(repeating: 0xAB, count: 32)) }

    private func makeClient(
        token: RecordingTokenRequesting,
        browser: StubBrowserAuthorizationSession
    ) -> OAuthClient {
        OAuthClient(
            discovery: FakeAccountDiscovering(result: discovery()),
            authorizationRequester: FakeAuthorizationRequesting(
                response: PushedAuthorizationResponse(requestURI: "urn:req:1", expiresIn: 60)
            ),
            tokenRequester: token,
            browser: browser,
            random: StubRandomBytesGenerator(),
            sha256: { $0 },
            config: .yoruMimizuku
        )
    }

    func testLoginCompletesFullFlow() async throws {
        let token = RecordingTokenRequesting(response: tokenResponse())
        // Realistic browser: the authorization server returns state in the redirect.
        let state = expectedState
        let browser = StubBrowserAuthorizationSession { _, scheme in
            URL(string: "\(scheme):/callback?code=THE_CODE&state=\(state)")!
        }
        let client = makeClient(token: token, browser: browser)

        let result = try await client.login(account: "alice.bsky.social")

        // Returned session carries DID, PDS and tokens.
        XCTAssertEqual(result.did, "did:plc:abc")
        XCTAssertEqual(result.pds, URL(string: "https://pds.example")!)
        XCTAssertEqual(result.tokens.accessToken, "atk")
        XCTAssertEqual(result.tokens.refreshToken, "rtk")

        // Browser opened the authorization URL built from the PAR request_uri,
        // using the redirect scheme.
        XCTAssertEqual(browser.openedScheme, "as.ason")
        let opened = URLComponents(url: browser.openedURL!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(opened?.host, "bsky.social")
        XCTAssertEqual(opened?.path, "/oauth/authorize")
        let openedItems = Dictionary(
            uniqueKeysWithValues: (opened?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(openedItems["request_uri"], "urn:req:1")

        // Token exchange used the authorization_code grant with the PKCE verifier
        // and the code from the callback.
        XCTAssertEqual(
            token.lastGrant,
            .authorizationCode(code: "THE_CODE", codeVerifier: expectedVerifier)
        )
    }

    func testLoginThrowsStateMismatchWhenCallbackStateDiffers() async {
        let token = RecordingTokenRequesting(response: tokenResponse())
        let browser = StubBrowserAuthorizationSession { _, scheme in
            URL(string: "\(scheme):/callback?code=THE_CODE&state=WRONG")!
        }
        let client = makeClient(token: token, browser: browser)

        do {
            _ = try await client.login(account: "alice.bsky.social")
            XCTFail("expected error")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .stateMismatch)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // Token exchange must not happen on a state mismatch.
        XCTAssertNil(token.lastGrant)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter OAuthClientTests`
Expected: FAIL — `cannot find 'OAuthClient' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
import Foundation

/// The result of a successful OAuth login: the account DID (authoritative `sub`
/// from the token response), its PDS, the authorization server issuer, and the
/// issued tokens. The platform layer persists these.
public struct OAuthLoginResult: Equatable, Sendable {
    public let did: String
    public let pds: URL
    public let authorizationServerIssuer: String
    public let tokens: TokenResponse
}

/// Orchestrates the full atproto OAuth login: discovery → PKCE/state → PAR →
/// authorization URL → browser approval → callback parsing + state check →
/// token exchange. All collaborators are injected so the whole flow is testable
/// with fakes.
public struct OAuthClient: Sendable {
    private let discovery: AccountDiscovering
    private let authorizationRequester: AuthorizationRequesting
    private let tokenRequester: TokenRequesting
    private let browser: BrowserAuthorizationSession
    private let random: RandomBytesGenerator
    private let sha256: @Sendable (Data) -> Data
    private let config: OAuthClientConfig

    public init(
        discovery: AccountDiscovering,
        authorizationRequester: AuthorizationRequesting,
        tokenRequester: TokenRequesting,
        browser: BrowserAuthorizationSession,
        random: RandomBytesGenerator,
        sha256: @escaping @Sendable (Data) -> Data,
        config: OAuthClientConfig
    ) {
        self.discovery = discovery
        self.authorizationRequester = authorizationRequester
        self.tokenRequester = tokenRequester
        self.browser = browser
        self.random = random
        self.sha256 = sha256
        self.config = config
    }

    public func login(account: String) async throws -> OAuthLoginResult {
        let discovered = try await discovery.discover(account: account)

        let verifier = PKCE.generateVerifier(randomBytes: random.bytes)
        let pkce = PKCE.make(verifier: verifier, sha256: sha256)
        let state = AuthorizationRequest.generateState(randomBytes: random.bytes)

        let request = AuthorizationRequest(
            config: config, pkce: pkce, state: state, loginHint: account
        )
        let par = try await authorizationRequester.push(
            metadata: discovered.metadata, request: request
        )
        let authorizationURL = try AuthorizationRequestService.authorizationURL(
            metadata: discovered.metadata, config: config, requestURI: par.requestURI
        )

        let callbackURL = try await browser.authenticate(
            url: authorizationURL, callbackScheme: config.callbackScheme
        )
        let callback = try OAuthCallback.parse(url: callbackURL)
        guard callback.state == state else {
            throw OAuthError.stateMismatch
        }

        let tokens = try await tokenRequester.requestToken(
            metadata: discovered.metadata,
            config: config,
            grant: .authorizationCode(code: callback.code, codeVerifier: verifier)
        )
        return OAuthLoginResult(
            did: tokens.sub,
            pds: discovered.pds,
            authorizationServerIssuer: discovered.authorizationServerIssuer,
            tokens: tokens
        )
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter OAuthClientTests`
Expected: PASS (2 cases).

- [ ] **Step 6: Run the full suite**

Run: `swift test --package-path BlueskyCore`
Expected: all tests pass (71 prior + the new ones).

- [ ] **Step 7: Commit**

Use the `/commit` skill. Stage `OAuthClient.swift` + `Support/OAuthClientFakes.swift` + `OAuthClientTests.swift`. Behavioral change. Suggested message: `Add OAuth login orchestrator`.

---

## Self-Review

- **Spec coverage:** §5.2 のフロー全体（identity 解決〜トークン交換）を `OAuthClient.login` が一本につなぐ。step 4 のブラウザ部分は `BrowserAuthorizationSession` 抽象として満たし（実体は次プラン）、step 1/2/3/5 は既存サービスへ委譲。§4 の「OAuth ステートマシンは OS 非依存」を、ブラウザ/乱数をプロトコルで抽象化することで満たす。OS 乱数の Apple 実体（`SecRandomBytesGenerator`）は §4 の touchpoint #?（乱数）を埋める。
- **Placeholder scan:** TBD/TODO なし。各コードステップは完全。Task 4/5 はテストを持たないが、いずれも「純粋なプロトコル宣言/conformance」であり、Task 6 の end-to-end テストで実際に行使される（フェイクが conform するだけのテストは testing-of-mocks アンチパターンになるため意図的に置かない）。
- **Type consistency:** `OAuthClient.login(account:) -> OAuthLoginResult`、`RandomBytesGenerator.bytes(_:)`、`OAuthCallback.parse(url:)`、`BrowserAuthorizationSession.authenticate(url:callbackScheme:)`、`AccountDiscovering.discover(account:)` / `AuthorizationRequesting.push(metadata:request:)` / `TokenRequesting.requestToken(metadata:config:grant:)` は全タスクで同一。これらは既存の `OAuthDiscovery.discover(account:)` / `AuthorizationRequestService.push(metadata:request:)` / `TokenService.requestToken(metadata:config:grant:)` と一致（Task 5 の conformance が成立する根拠）。`PushedAuthorizationResponse(requestURI:expiresIn:)` と `OAuthDiscovery.Result(did:pds:authorizationServerIssuer:metadata:)` はメンバワイズ初期化子（両 struct とも public let のみで明示 init 無し → メンバワイズ init が public 合成される）を使用。`TokenResponse` は Decodable のみのため、テストでは JSON デコードで生成している。

> 実装注意: `OAuthDiscovery.Result` と `PushedAuthorizationResponse` をテストでメンバワイズ初期化子から生成する。もし将来これらに明示初期化子が無くメンバワイズ init が internal 扱いでテストから見えない場合は、`@testable import BlueskyCore` で解決済み（テストは同モジュール扱い）。問題が出たら public memberwise init を足さず、テスト側のデコード生成に切り替えること。

## Carry-forward to next plan (platform + app)

- `ASWebAuthenticationSession` を `BrowserAuthorizationSession` に適合させる Apple 実体（presentation anchor、`prefersEphemeralWebBrowserSession` の検討、ユーザーキャンセルのエラー写像）。
- Keychain への per-DID トークン保管 + DPoP 秘密鍵（CryptoKit P-256）保管、`AccountManager` / `SessionStore`、期限切れ時の `TokenGrant.refresh` 自動実行。
- `OAuthClient` を実コラボレータ（`OAuthDiscovery(http:)` / `AuthorizationRequestService(sender:)` / `TokenService(sender:)` / `SecRandomBytesGenerator` / `CryptoKitDPoPProvider.sha256`）で組み立てる便宜初期化子。
- macOS アプリのログイン UI（handle 入力 → `login(account:)` 起動 → 成功で `AccountManager` に保存 → メインウィンドウへ）。
