# YoruMimizuku OAuth PKCE + DPoP Sender Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OAuth 認可フローが依存する 2 つの再利用プリミティブを `BlueskyCore` に実装する。(1) PKCE（code_verifier / code_challenge=S256）、(2) DPoP 付きリクエスト送信ラッパー（`use_dpop_nonce` の 1 回リトライを内包）。両方とも純粋・OS 非依存で、フェイク注入で決定論的にテストする。

**Architecture:** PKCE は SHA-256 を注入クロージャとして受け取り（本番配線では `DPoPCryptoProvider.sha256` を渡して再利用）、`Base64URL`（Plan 2）で challenge を作る。`DPoPRequestSender` は `HTTPClient`（Plan 1）と `DPoPProofBuilder`（Plan 2）を束ね、リクエストに DPoP proof（と任意の Authorization）ヘッダを付けて送信し、サーバが `use_dpop_nonce` を返したら応答の `DPoP-Nonce` ヘッダで proof を作り直して 1 回だけ再送する。順序付きフェイク（`SequencedHTTPClient`）でリトライ経路を検証する。

**Tech Stack:** Swift 6 / Swift Package Manager / XCTest / Foundation / CryptoKit（PKCE 統合テストの実 SHA-256 のみ）。既存 `BlueskyCore`（macOS 14+/iOS 17+）に追加。

このプランは設計書 `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md` の §5.2 ステップ3（PKCE）・§5.3（DPoP の `use_dpop_nonce` 1 回リトライ）に対応する。PAR・認可URL構築・トークン交換/リフレッシュは次プラン、`ASWebAuthenticationSession`・Keychain・`AccountManager`・アプリ結線はその後。

## 前提・作業ルール

- リポジトリ: `/Users/asonas/workspace/yorumimizuku`（main に Plan 1–4 マージ済み）
- worktree: `git -C /Users/asonas/workspace/yorumimizuku wt feature/oauth-pkce-dpop` → `<wt>` = `/Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop`
- コミットは `git -C <wt> ai-commit`（`git commit` 直接実行禁止。ai-commit 不可なら中断して報告）
- テスト: `swift test --package-path BlueskyCore`（`<wt>` 内）
- 1 テストずつ Red → Green → Refactor
- 既存資産の再利用: `Base64URL`・`DPoPProofBuilder`・`DPoPCryptoProvider`・`FakeDPoPCryptoProvider`（Plan 2）、`HTTPClient`/`HTTPRequest`/`HTTPResponse`/`HTTPMethod`（Plan 1）、`XRPCErrorResponse`（Plan 1）

## File Structure

- `BlueskyCore/Sources/BlueskyCore/OAuth/PKCE.swift` — PKCE 値型＋生成
- `BlueskyCore/Sources/BlueskyCore/OAuth/DPoPRequestSender.swift` — DPoP 付き送信＋nonce リトライ
- `BlueskyCore/Tests/BlueskyCoreTests/PKCETests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/Support/SequencedHTTPClient.swift` — 順序付きレスポンスを返すテスト用フェイク
- `BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift`

---

### Task 1: PKCE

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/PKCETests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/PKCE.swift`

- [ ] **Step 0: worktree 作成**

Run: `git -C /Users/asonas/workspace/yorumimizuku wt feature/oauth-pkce-dpop`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/PKCETests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class PKCETests: XCTestCase {
    func test_make_computesChallengeAsBase64URLOfHash() {
        // Fake sha256 returns fixed bytes, so the challenge is deterministic.
        let fixed = Data([0x01, 0x02, 0x03, 0x04])
        let pkce = PKCE.make(verifier: "the-verifier", sha256: { _ in fixed })

        XCTAssertEqual(pkce.codeVerifier, "the-verifier")
        XCTAssertEqual(pkce.codeChallenge, "AQIDBA")  // base64url(0x01020304) without padding
        XCTAssertEqual(pkce.codeChallengeMethod, "S256")
    }

    func test_make_matchesRFC7636TestVectorWithRealSHA256() {
        // RFC 7636 Appendix B test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let pkce = PKCE.make(verifier: verifier, sha256: CryptoKitDPoPProvider().sha256)

        XCTAssertEqual(pkce.codeChallenge, expectedChallenge)
    }

    func test_generateVerifier_is43CharBase64URLFrom32Bytes() {
        let bytes = Data(repeating: 0xAB, count: 32)
        let verifier = PKCE.generateVerifier(randomBytes: { count in
            XCTAssertEqual(count, 32)
            return bytes
        })

        // 32 bytes base64url-encoded (no padding) == 43 characters, URL-safe alphabet only.
        XCTAssertEqual(verifier.count, 43)
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter PKCETests`
Expected: FAIL（`PKCE` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/PKCE.swift`:
```swift
import Foundation

/// PKCE (RFC 7636) parameters for an OAuth authorization. `codeChallenge` is the
/// base64url of SHA-256(`codeVerifier`); the method is always S256 for atproto.
public struct PKCE: Equatable, Sendable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String

    public init(codeVerifier: String, codeChallenge: String, codeChallengeMethod: String = "S256") {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }

    /// Build a PKCE pair from a verifier, hashing with the supplied SHA-256.
    /// In production pass `DPoPCryptoProvider.sha256`; tests pass a fake.
    public static func make(verifier: String, sha256: (Data) -> Data) -> PKCE {
        let challenge = Base64URL.encode(sha256(Data(verifier.utf8)))
        return PKCE(codeVerifier: verifier, codeChallenge: challenge, codeChallengeMethod: "S256")
    }

    /// Generate a code verifier as base64url of 32 random bytes (43 chars, within
    /// the RFC 7636 43–128 length range). `randomBytes` is injected for testability.
    public static func generateVerifier(randomBytes: (Int) -> Data) -> String {
        Base64URL.encode(randomBytes(32))
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter PKCETests`
Expected: PASS（3 テスト。特に RFC 7636 ベクタ一致が実 SHA-256 の正しさを保証）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop add BlueskyCore/Sources/BlueskyCore/OAuth/PKCE.swift BlueskyCore/Tests/BlueskyCoreTests/PKCETests.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop ai-commit
```
メッセージ例: `Add PKCE generation`

---

### Task 2: SequencedHTTPClient と DPoPRequestSender（リトライなしの正常系）

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/SequencedHTTPClient.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/DPoPRequestSender.swift`

- [ ] **Step 1: 順序付きフェイクを実装**

Create `BlueskyCore/Tests/BlueskyCoreTests/Support/SequencedHTTPClient.swift`:
```swift
import Foundation
@testable import BlueskyCore

/// Test `HTTPClient` that returns queued responses in order (one per call). Used
/// to drive multi-step flows like the DPoP nonce retry. `@unchecked Sendable`:
/// used serially within async tests.
final class SequencedHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [HTTPResponse]
    private(set) var sentRequests: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        guard !responses.isEmpty else {
            return HTTPResponse(statusCode: 500, body: Data())
        }
        return responses.removeFirst()
    }
}
```

- [ ] **Step 2: 正常系テストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class DPoPRequestSenderTests: XCTestCase {
    private func makeSender(_ http: HTTPClient) -> DPoPRequestSender {
        let builder = DPoPProofBuilder(
            crypto: FakeDPoPCryptoProvider(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "fixed-jti" }
        )
        return DPoPRequestSender(http: http, proofBuilder: builder)
    }

    func test_send_attachesDPoPHeaderAndReturnsResponseWithoutRetry() async throws {
        let http = SequencedHTTPClient([
            HTTPResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!,
            body: Data("x".utf8)
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(http.sentRequests.count, 1)
        XCTAssertNotNil(http.sentRequests.first?.headers["DPoP"], "the request must carry a DPoP proof")
    }

    func test_send_addsAuthorizationHeaderWhenAccessTokenGiven() async throws {
        let http = SequencedHTTPClient([HTTPResponse(statusCode: 200, body: Data("{}".utf8))])
        let sender = makeSender(http)

        _ = try await sender.send(
            method: .get,
            url: URL(string: "https://pds.example.com/xrpc/app.bsky.feed.getTimeline")!,
            accessToken: "access-token-123"
        )

        XCTAssertEqual(http.sentRequests.first?.headers["Authorization"], "DPoP access-token-123")
    }
}
```

- [ ] **Step 3: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter DPoPRequestSenderTests`
Expected: FAIL（`DPoPRequestSender` 未定義）。

- [ ] **Step 4: 実装（正常系＋リトライ判定の骨組み）**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/DPoPRequestSender.swift`:
```swift
import Foundation

/// Sends HTTP requests carrying a DPoP proof, transparently handling the
/// `use_dpop_nonce` challenge: if the server rejects the first attempt and supplies
/// a `DPoP-Nonce`, the proof is rebuilt with that nonce and the request is retried
/// exactly once. Used by PAR and token exchange.
public struct DPoPRequestSender: Sendable {
    private let http: HTTPClient
    private let proofBuilder: DPoPProofBuilder

    public init(http: HTTPClient, proofBuilder: DPoPProofBuilder) {
        self.http = http
        self.proofBuilder = proofBuilder
    }

    public func send(
        method: HTTPMethod,
        url: URL,
        accessToken: String? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        let first = try await sendOnce(
            method: method, url: url, accessToken: accessToken,
            nonce: nil, headers: headers, body: body
        )
        guard Self.isNonceChallenge(first), let nonce = Self.dpopNonce(in: first.headers) else {
            return first
        }
        return try await sendOnce(
            method: method, url: url, accessToken: accessToken,
            nonce: nonce, headers: headers, body: body
        )
    }

    private func sendOnce(
        method: HTTPMethod,
        url: URL,
        accessToken: String?,
        nonce: String?,
        headers: [String: String],
        body: Data?
    ) async throws -> HTTPResponse {
        let proof = try proofBuilder.makeProof(
            method: method, url: url, accessToken: accessToken, nonce: nonce
        )
        var merged = headers
        merged["DPoP"] = proof
        if let accessToken {
            merged["Authorization"] = "DPoP \(accessToken)"
        }
        return try await http.send(HTTPRequest(url: url, method: method, headers: merged, body: body))
    }

    /// True when the response is a `use_dpop_nonce` challenge (400/401 whose error body
    /// is `use_dpop_nonce`).
    static func isNonceChallenge(_ response: HTTPResponse) -> Bool {
        guard response.statusCode == 400 || response.statusCode == 401 else { return false }
        guard let error = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body) else {
            return false
        }
        return error.error == "use_dpop_nonce"
    }

    /// Case-insensitive lookup of the `DPoP-Nonce` response header.
    static func dpopNonce(in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare("DPoP-Nonce") == .orderedSame }?.value
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DPoPRequestSenderTests`
Expected: PASS（2 テスト）。

- [ ] **Step 6: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop add BlueskyCore/Sources/BlueskyCore/OAuth/DPoPRequestSender.swift BlueskyCore/Tests/BlueskyCoreTests/Support/SequencedHTTPClient.swift BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop ai-commit
```
メッセージ例: `Add DPoP request sender with nonce challenge detection`

---

### Task 3: DPoPRequestSender の nonce リトライ経路

**Files:**
- Modify: `BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift`（テスト追加。実装は Task 2 で対応済み）

- [ ] **Step 1: リトライ経路のテストを追加**

`DPoPRequestSenderTests` クラスに以下を追加。2 回目の proof の `nonce` クレームをデコードして検証する（`FakeDPoPCryptoProvider` の proof は base64url JSON なのでデコード可能）:
```swift
    struct ProofClaims: Decodable {
        let htm: String
        let htu: String
        let nonce: String?
    }

    private func decodeClaims(fromDPoPHeader proof: String) throws -> ProofClaims {
        let segments = proof.split(separator: ".")
        let payload = try XCTUnwrap(Base64URL.decode(String(segments[1])))
        return try JSONDecoder().decode(ProofClaims.self, from: payload)
    }

    func test_send_retriesOnceWithServerNonce() async throws {
        let challenge = HTTPResponse(
            statusCode: 400,
            headers: ["DPoP-Nonce": "server-nonce-1"],
            body: Data(#"{"error":"use_dpop_nonce"}"#.utf8)
        )
        let success = HTTPResponse(statusCode: 200, body: Data("{}".utf8))
        let http = SequencedHTTPClient([challenge, success])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!,
            body: Data("x".utf8)
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(http.sentRequests.count, 2, "should retry exactly once")

        // First attempt has no nonce; the retry carries the server nonce.
        let firstProof = try XCTUnwrap(http.sentRequests[0].headers["DPoP"])
        let retryProof = try XCTUnwrap(http.sentRequests[1].headers["DPoP"])
        XCTAssertNil(try decodeClaims(fromDPoPHeader: firstProof).nonce)
        XCTAssertEqual(try decodeClaims(fromDPoPHeader: retryProof).nonce, "server-nonce-1")
    }

    func test_send_doesNotRetryWhenNonceChallengeLacksNonceHeader() async throws {
        // 400 use_dpop_nonce but NO DPoP-Nonce header -> cannot retry, return as-is.
        let challenge = HTTPResponse(
            statusCode: 400,
            body: Data(#"{"error":"use_dpop_nonce"}"#.utf8)
        )
        let http = SequencedHTTPClient([challenge, HTTPResponse(statusCode: 200, body: Data())])
        let sender = makeSender(http)

        let response = try await sender.send(
            method: .post,
            url: URL(string: "https://bsky.social/oauth/par")!
        )

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(http.sentRequests.count, 1, "no retry without a nonce to use")
    }
```

- [ ] **Step 2: テストを実行**

Run: `swift test --package-path BlueskyCore --filter DPoPRequestSenderTests`
Expected: PASS（Task 2 の実装がリトライを処理済み）。FAIL する場合はテストを書き換えず `send`/`isNonceChallenge`/`dpopNonce` を見直す。

- [ ] **Step 3: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop add BlueskyCore/Tests/BlueskyCoreTests/DPoPRequestSenderTests.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/oauth-pkce-dpop ai-commit
```
メッセージ例: `Cover DPoP nonce retry path`

---

### Task 4: 全テスト緑の確認と仕上げ

**Files:** なし（検証のみ）

- [ ] **Step 1: 全テスト**

Run: `swift test --package-path BlueskyCore`
Expected: 既存（42）＋ 本プランの新規テストがすべて PASS。

- [ ] **Step 2: リリースビルド**

Run: `swift build --package-path BlueskyCore -c release`
Expected: 成功、警告なし。

- [ ] **Step 3: ブランチ仕上げ**

`superpowers:finishing-a-development-branch` に従い `feature/oauth-pkce-dpop` の取り込み方法を選ぶ。

---

## Self-Review

**1. Spec coverage:**
- §5.2 ステップ3（PKCE: code_verifier / code_challenge=S256）→ Task 1（`PKCE`）。
- §5.3（DPoP の `use_dpop_nonce` 1 回リトライ）→ Task 2/3（`DPoPRequestSender`）。
- 本プラン対象外（後続）: PAR・認可URL構築・トークン交換/リフレッシュ・`ASWebAuthenticationSession`・Keychain・`AccountManager`・アプリ結線。スコープ逸脱なし。

**2. Placeholder scan:** プレースホルダなし。各コードステップは完全なコードを含む。

**3. Type consistency:**
- `PKCE.make(verifier:sha256:)` / `PKCE.generateVerifier(randomBytes:)` / `PKCE(codeVerifier:codeChallenge:codeChallengeMethod:)` は Task 1 定義とテストで一致。`Base64URL`（Plan 2、内部）を利用。RFC 7636 ベクタ検証は `CryptoKitDPoPProvider().sha256`（Plan 2）を渡す。
- `DPoPRequestSender(http:proofBuilder:)` / `send(method:url:accessToken:headers:body:)` / `static isNonceChallenge(_:)` / `static dpopNonce(in:)` は Task 2 定義、Task 2/3 テストで一致。
- `DPoPProofBuilder(crypto:now:makeJTI:)` と `makeProof(method:url:accessToken:nonce:)`（Plan 2）を利用。`FakeDPoPCryptoProvider`（Plan 2）で proof を決定論化し、Task 3 は proof の `nonce` クレームをデコードして検証。
- `XRPCErrorResponse`（Plan 1、`{error,message?}`）を `use_dpop_nonce` 判定に再利用。
- `HTTPClient`/`HTTPRequest`/`HTTPResponse`/`HTTPMethod`（Plan 1）を利用。`SequencedHTTPClient` は順序付きレスポンスのテスト用フェイク。

## 次プラン（PAR + 認可URL構築）への申し送り
- `OAuthDiscovery.Result`（Plan 4）＋ クライアント設定（client_id=`https://ason.as/yorumimizuku/client-metadata.json`、redirect_uri=`as.ason:/callback`、scope=`atproto transition:generic`）＋ `PKCE` ＋ state を入力に、`DPoPRequestSender.send` で PAR エンドポイントへ POST（フォームエンコード body）→ `request_uri` 取得 → 認可URL `<authorization_endpoint>?client_id=...&request_uri=...` を構築する。
- PAR の body は `application/x-www-form-urlencoded`（JSON ではない）。フォームエンコードのヘルパーが要る。`DPoPRequestSender.send` は body/Content-Type を渡せるよう `headers` で `Content-Type` を指定する。
- state（CSRF 対策のランダム値）と `PKCE` は認可後のコールバックで照合・トークン交換に使うため、呼び出し側で保持する（次プランで `AuthorizationState` 的な型に束ねる）。
- 乱数源（`generateVerifier`/state 用）の OS 実装（SecRandom 等）は、ブラウザ/Keychain を扱うプラットフォームプランで `RandomBytesGenerator` として用意する。本プランの PKCE は乱数を注入式にしてあるので接続は容易。
