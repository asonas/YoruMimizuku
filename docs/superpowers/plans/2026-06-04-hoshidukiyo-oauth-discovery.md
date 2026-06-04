# Hoshidukiyo OAuth Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `BlueskyCore` に atproto OAuth の「ディスカバリ層」を実装する。入力された handle / DID から、DID・PDS エンドポイント・認可サーバ（authorization server）のメタデータ（authorization / token / PAR エンドポイント）まで解決する。すべて純粋な HTTP + JSON で、ネットワークは `HTTPClient` 抽象越しにフェイク注入してテストする。

**Architecture:** OS 非依存。`HTTPClient`（Plan 1）越しに well-known / DID document / XRPC を GET し、JSON を Codable モデルへデコードする。`IdentityResolver` が handle→DID→PDS を、`OAuthMetadataResolver` が PDS→protected-resource→authorization-server を解決し、`OAuthDiscovery` が両者を束ねて 1 アカウント分の解決結果を返す。多段の HTTP 呼び出しは URL ルーティング可能なテスト用フェイク（`RoutingHTTPClient`）で検証する。新しい暗号は導入しない。

**Tech Stack:** Swift 6 / Swift Package Manager / XCTest / Foundation。既存 `BlueskyCore`（macOS 14+/iOS 17+）に追加。

このプランは設計書 `docs/superpowers/specs/2026-06-04-hoshidukiyo-design.md` の §5.2 ステップ1–2（identity 解決・authz server discovery）に対応する。PKCE・PAR・認可URL構築・トークン交換・nonce 再試行は次プラン、`ASWebAuthenticationSession`・Keychain・`AccountManager`・アプリ結線はその次のプラン。

## 前提・作業ルール

- リポジトリ: `/Users/asonas/workspace/hoshidukiyo`（main に Plan 1/2/3 マージ済み）
- worktree で実装:
  ```bash
  git -C /Users/asonas/workspace/hoshidukiyo wt feature/oauth-discovery
  ```
  worktree: `/Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery`（以降 `<wt>`）
- コミットは `git ai-commit`（`git commit` 直接実行禁止）
- テスト: `swift test --package-path BlueskyCore`（`<wt>` 内で実行）
- 1テストずつ Red → Green → Refactor

## 背景知識（実装者向け、atproto OAuth ディスカバリ）

1. handle → DID: `GET <directory>/xrpc/com.atproto.identity.resolveHandle?handle=<handle>` が `{"did": "..."}` を返す（directory は既定で `https://bsky.social`）。入力が既に DID（`did:` 始まり）ならこの段は省く。
2. DID → PDS: DID document を取得し、`service` 配列から atproto PDS のエンドポイントを得る。
   - `did:plc:*` → `GET https://plc.directory/<did>`
   - `did:web:<host>` → `GET https://<host>/.well-known/did.json`
   - PDS は `service` の要素で `id` が `#atproto_pds` で終わる、または `type == "AtprotoPersonalDataServer"` のものの `serviceEndpoint`。
3. PDS → 認可サーバ: `GET <pds>/.well-known/oauth-protected-resource` が `{"authorization_servers": ["<as>"]}` を返す。
4. 認可サーバメタデータ: `GET <as>/.well-known/oauth-authorization-server` が `issuer` / `authorization_endpoint` / `token_endpoint` / `pushed_authorization_request_endpoint` などを返す。

## File Structure

- `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift` — ディスカバリのエラー型
- `BlueskyCore/Sources/BlueskyCore/OAuth/DIDDocument.swift` — DID document モデル＋ PDS 抽出
- `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthServerMetadata.swift` — protected-resource / authorization-server メタデータ
- `BlueskyCore/Sources/BlueskyCore/OAuth/JSONGet.swift` — JSON GET ヘルパー（内部）
- `BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift` — handle→DID, DID→PDS
- `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthMetadataResolver.swift` — PDS→protected-resource→authorization-server
- `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthDiscovery.swift` — 全体オーケストレーション
- `BlueskyCore/Tests/BlueskyCoreTests/Support/RoutingHTTPClient.swift` — URL ルーティング可能なテスト用フェイク
- `BlueskyCore/Tests/BlueskyCoreTests/DIDDocumentTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/OAuthServerMetadataTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/OAuthMetadataResolverTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/OAuthDiscoveryTests.swift`

---

### Task 1: OAuthError と DID document モデル

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/DIDDocumentTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/DIDDocument.swift`

- [ ] **Step 0: worktree 作成**

Run: `git -C /Users/asonas/workspace/hoshidukiyo wt feature/oauth-discovery`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/DIDDocumentTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class DIDDocumentTests: XCTestCase {
    func test_decodesAndExtractsPDSByServiceId() throws {
        let json = Data(#"""
        {
          "id": "did:plc:abc123",
          "service": [
            {"id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "https://pds.example.com"}
          ]
        }
        """#.utf8)

        let doc = try JSONDecoder().decode(DIDDocument.self, from: json)

        XCTAssertEqual(doc.id, "did:plc:abc123")
        XCTAssertEqual(doc.pdsEndpoint, URL(string: "https://pds.example.com"))
    }

    func test_pdsEndpoint_isNilWhenNoAtprotoService() throws {
        let json = Data(#"{"id":"did:plc:x","service":[{"id":"#other","type":"Foo","serviceEndpoint":"https://nope.example"}]}"#.utf8)

        let doc = try JSONDecoder().decode(DIDDocument.self, from: json)

        XCTAssertNil(doc.pdsEndpoint)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter DIDDocumentTests`
Expected: FAIL（`DIDDocument` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift`:
```swift
import Foundation

/// Errors from the OAuth discovery layer.
public enum OAuthError: Error, Equatable {
    /// A discovery HTTP GET returned a non-2xx status.
    case discoveryFailed(url: String, status: Int)
    /// A required field was missing or unparseable in a discovery document.
    case malformedDocument(String)
    /// The DID could not be resolved to a PDS endpoint.
    case pdsNotFound(did: String)
    /// The DID method is not supported by this client.
    case unsupportedDIDMethod(String)
}
```

Create `BlueskyCore/Sources/BlueskyCore/OAuth/DIDDocument.swift`:
```swift
import Foundation

/// The subset of a DID document needed to find an account's PDS.
public struct DIDDocument: Decodable, Equatable, Sendable {
    public struct Service: Decodable, Equatable, Sendable {
        public let id: String
        public let type: String
        public let serviceEndpoint: String
    }

    public let id: String
    public let service: [Service]

    /// The atproto Personal Data Server endpoint, if present.
    public var pdsEndpoint: URL? {
        let match = service.first {
            $0.id.hasSuffix("#atproto_pds") || $0.type == "AtprotoPersonalDataServer"
        }
        return match.flatMap { URL(string: $0.serviceEndpoint) }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DIDDocumentTests`
Expected: PASS（2 テスト）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/OAuthError.swift BlueskyCore/Sources/BlueskyCore/OAuth/DIDDocument.swift BlueskyCore/Tests/BlueskyCoreTests/DIDDocumentTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
`git ai-commit` が使えない場合は中断して報告。メッセージ例: `Add DID document model and OAuth error type`

---

### Task 2: OAuth サーバメタデータのモデル

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/OAuthServerMetadataTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthServerMetadata.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/OAuthServerMetadataTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class OAuthServerMetadataTests: XCTestCase {
    func test_decodesProtectedResourceAuthorizationServers() throws {
        let json = Data(#"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#.utf8)

        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: json)

        XCTAssertEqual(metadata.authorizationServers, ["https://bsky.social"])
    }

    func test_decodesAuthorizationServerEndpoints() throws {
        let json = Data(#"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token",
          "pushed_authorization_request_endpoint": "https://bsky.social/oauth/par"
        }
        """#.utf8)

        let metadata = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: json)

        XCTAssertEqual(metadata.issuer, "https://bsky.social")
        XCTAssertEqual(metadata.authorizationEndpoint, "https://bsky.social/oauth/authorize")
        XCTAssertEqual(metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter OAuthServerMetadataTests`
Expected: FAIL（型未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthServerMetadata.swift`:
```swift
import Foundation

/// `/.well-known/oauth-protected-resource` on the PDS: points at the
/// authorization server(s) that protect this resource.
public struct ProtectedResourceMetadata: Decodable, Equatable, Sendable {
    public let authorizationServers: [String]

    enum CodingKeys: String, CodingKey {
        case authorizationServers = "authorization_servers"
    }
}

/// `/.well-known/oauth-authorization-server`: the endpoints the OAuth flow uses.
public struct AuthorizationServerMetadata: Decodable, Equatable, Sendable {
    public let issuer: String
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let pushedAuthorizationRequestEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter OAuthServerMetadataTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/OAuthServerMetadata.swift BlueskyCore/Tests/BlueskyCoreTests/OAuthServerMetadataTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
メッセージ例: `Add OAuth server metadata models`

---

### Task 3: JSON GET ヘルパーとルーティング可能なテスト用フェイク、IdentityResolver.resolveHandle

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/JSONGet.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/RoutingHTTPClient.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift`

- [ ] **Step 1: JSON GET ヘルパーを実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/JSONGet.swift`:
```swift
import Foundation

/// Performs a plain JSON GET via the injected `HTTPClient`, decoding the body or
/// throwing `OAuthError.discoveryFailed` on non-2xx. Used by the discovery layer
/// (well-known docs, DID documents) which are plain GETs rather than XRPC calls.
func getDiscoveryJSON<T: Decodable>(
    _ url: URL,
    http: HTTPClient,
    decoder: JSONDecoder = JSONDecoder()
) async throws -> T {
    let request = HTTPRequest(url: url, method: .get, headers: ["Accept": "application/json"])
    let response = try await http.send(request)
    guard (200..<300).contains(response.statusCode) else {
        throw OAuthError.discoveryFailed(url: url.absoluteString, status: response.statusCode)
    }
    do {
        return try decoder.decode(T.self, from: response.body)
    } catch {
        throw OAuthError.malformedDocument(url.absoluteString)
    }
}
```

- [ ] **Step 2: ルーティング可能なテスト用フェイクを実装**

Create `BlueskyCore/Tests/BlueskyCoreTests/Support/RoutingHTTPClient.swift`:
```swift
import Foundation
@testable import BlueskyCore

/// Test `HTTPClient` that returns a response based on the request URL. Routes are
/// matched in order; the first whose predicate matches wins. Used for multi-step
/// discovery flows where each GET hits a different URL. Marked `@unchecked
/// Sendable`: used serially within async tests.
final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    struct Route {
        let matches: (URL) -> Bool
        let response: HTTPResponse
    }

    private let routes: [Route]
    private(set) var sentRequests: [HTTPRequest] = []

    init(routes: [Route]) {
        self.routes = routes
    }

    /// Convenience: route by exact absolute-string match returning a 200 JSON body.
    static func json(_ pairs: [(url: String, body: String)]) -> RoutingHTTPClient {
        RoutingHTTPClient(routes: pairs.map { pair in
            Route(
                matches: { $0.absoluteString == pair.url },
                response: HTTPResponse(statusCode: 200, body: Data(pair.body.utf8))
            )
        })
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        if let route = routes.first(where: { $0.matches(request.url) }) {
            return route.response
        }
        return HTTPResponse(statusCode: 404, body: Data())
    }
}
```

- [ ] **Step 3: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class IdentityResolverTests: XCTestCase {
    func test_resolveHandleToDID_callsResolveHandleAndReturnsDID() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social",
                body: #"{"did":"did:plc:abc123"}"#
            )
        ])
        let resolver = IdentityResolver(http: http, directory: URL(string: "https://bsky.social")!)

        let did = try await resolver.resolveHandleToDID("asonas.bsky.social")

        XCTAssertEqual(did, "did:plc:abc123")
    }

    func test_resolveHandleToDID_returnsInputUnchangedWhenAlreadyDID() async throws {
        let http = RoutingHTTPClient(routes: [])
        let resolver = IdentityResolver(http: http, directory: URL(string: "https://bsky.social")!)

        let did = try await resolver.resolveHandleToDID("did:plc:already")

        XCTAssertEqual(did, "did:plc:already")
        XCTAssertTrue(http.sentRequests.isEmpty, "no network call should be made for a DID input")
    }
}
```

- [ ] **Step 4: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter IdentityResolverTests`
Expected: FAIL（`IdentityResolver` 未定義）。

- [ ] **Step 5: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift`:
```swift
import Foundation

/// Resolves a handle or DID to a DID, and a DID to its PDS endpoint.
public struct IdentityResolver: Sendable {
    private let http: HTTPClient
    private let directory: URL
    private let plcDirectory: URL

    public init(
        http: HTTPClient,
        directory: URL = URL(string: "https://bsky.social")!,
        plcDirectory: URL = URL(string: "https://plc.directory")!
    ) {
        self.http = http
        self.directory = directory
        self.plcDirectory = plcDirectory
    }

    /// Returns the input unchanged if it is already a DID; otherwise resolves the
    /// handle via `com.atproto.identity.resolveHandle`.
    public func resolveHandleToDID(_ handleOrDID: String) async throws -> String {
        if handleOrDID.hasPrefix("did:") {
            return handleOrDID
        }
        struct ResolveHandleResponse: Decodable { let did: String }
        var components = URLComponents(
            url: directory.appendingPathComponent("xrpc/com.atproto.identity.resolveHandle"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "handle", value: handleOrDID)]
        let response: ResolveHandleResponse = try await getDiscoveryJSON(components.url!, http: http)
        return response.did
    }
}
```

- [ ] **Step 6: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter IdentityResolverTests`
Expected: PASS（2 テスト）。

- [ ] **Step 7: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/JSONGet.swift BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift BlueskyCore/Tests/BlueskyCoreTests/Support/RoutingHTTPClient.swift BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
メッセージ例: `Add identity resolver handle-to-DID with routing test client`

---

### Task 4: IdentityResolver.resolveDIDToPDS（did:plc / did:web）

**Files:**
- Modify: `BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift`（テスト追加）
- Modify: `BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift`（メソッド追加）

- [ ] **Step 1: 失敗するテストを追加**

`IdentityResolverTests` クラスに以下を追加:
```swift
    func test_resolveDIDToPDS_plcFetchesPlcDirectory() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://plc.directory/did:plc:abc123",
                body: #"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"#
            )
        ])
        let resolver = IdentityResolver(http: http, plcDirectory: URL(string: "https://plc.directory")!)

        let pds = try await resolver.resolveDIDToPDS("did:plc:abc123")

        XCTAssertEqual(pds, URL(string: "https://pds.example.com"))
    }

    func test_resolveDIDToPDS_webFetchesWellKnownDIDJSON() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://example.com/.well-known/did.json",
                body: #"{"id":"did:web:example.com","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"#
            )
        ])
        let resolver = IdentityResolver(http: http)

        let pds = try await resolver.resolveDIDToPDS("did:web:example.com")

        XCTAssertEqual(pds, URL(string: "https://pds.example.com"))
    }

    func test_resolveDIDToPDS_throwsOnUnsupportedMethod() async {
        let resolver = IdentityResolver(http: RoutingHTTPClient(routes: []))
        do {
            _ = try await resolver.resolveDIDToPDS("did:example:foo")
            XCTFail("expected unsupportedDIDMethod")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .unsupportedDIDMethod("did:example:foo"))
        }
    }

    func test_resolveDIDToPDS_throwsWhenNoPDSInDocument() async {
        let http = RoutingHTTPClient.json([
            (url: "https://plc.directory/did:plc:x", body: #"{"id":"did:plc:x","service":[]}"#)
        ])
        let resolver = IdentityResolver(http: http)
        do {
            _ = try await resolver.resolveDIDToPDS("did:plc:x")
            XCTFail("expected pdsNotFound")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .pdsNotFound(did: "did:plc:x"))
        }
    }
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter IdentityResolverTests`
Expected: FAIL（`resolveDIDToPDS` 未定義）。

- [ ] **Step 3: メソッドを追加**

`IdentityResolver` に以下のメソッドを `resolveHandleToDID(_:)` の後へ追加:
```swift
    /// Resolves a DID to its PDS endpoint by fetching the DID document. Supports
    /// `did:plc` (via the PLC directory) and `did:web`.
    public func resolveDIDToPDS(_ did: String) async throws -> URL {
        let documentURL: URL
        if did.hasPrefix("did:plc:") {
            documentURL = plcDirectory.appendingPathComponent(did)
        } else if did.hasPrefix("did:web:") {
            let host = String(did.dropFirst("did:web:".count))
            guard let url = URL(string: "https://\(host)/.well-known/did.json") else {
                throw OAuthError.unsupportedDIDMethod(did)
            }
            documentURL = url
        } else {
            throw OAuthError.unsupportedDIDMethod(did)
        }

        let document: DIDDocument = try await getDiscoveryJSON(documentURL, http: http)
        guard let pds = document.pdsEndpoint else {
            throw OAuthError.pdsNotFound(did: did)
        }
        return pds
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter IdentityResolverTests`
Expected: PASS（6 テスト）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/IdentityResolver.swift BlueskyCore/Tests/BlueskyCoreTests/IdentityResolverTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
メッセージ例: `Resolve DID to PDS for plc and web methods`

---

### Task 5: OAuthMetadataResolver

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/OAuthMetadataResolverTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthMetadataResolver.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/OAuthMetadataResolverTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class OAuthMetadataResolverTests: XCTestCase {
    func test_protectedResource_fetchesWellKnownOnPDS() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://pds.example.com/.well-known/oauth-protected-resource",
                body: #"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#
            )
        ])
        let resolver = OAuthMetadataResolver(http: http)

        let metadata = try await resolver.protectedResource(pds: URL(string: "https://pds.example.com")!)

        XCTAssertEqual(metadata.authorizationServers, ["https://bsky.social"])
    }

    func test_authorizationServer_fetchesWellKnownOnIssuer() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/.well-known/oauth-authorization-server",
                body: #"{"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token","pushed_authorization_request_endpoint":"https://bsky.social/oauth/par"}"#
            )
        ])
        let resolver = OAuthMetadataResolver(http: http)

        let metadata = try await resolver.authorizationServer(issuer: URL(string: "https://bsky.social")!)

        XCTAssertEqual(metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter OAuthMetadataResolverTests`
Expected: FAIL（`OAuthMetadataResolver` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthMetadataResolver.swift`:
```swift
import Foundation

/// Resolves the OAuth well-known documents: the PDS's protected-resource
/// metadata and the authorization server's metadata.
public struct OAuthMetadataResolver: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public func protectedResource(pds: URL) async throws -> ProtectedResourceMetadata {
        let url = pds.appendingPathComponent(".well-known/oauth-protected-resource")
        return try await getDiscoveryJSON(url, http: http)
    }

    public func authorizationServer(issuer: URL) async throws -> AuthorizationServerMetadata {
        let url = issuer.appendingPathComponent(".well-known/oauth-authorization-server")
        return try await getDiscoveryJSON(url, http: http)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter OAuthMetadataResolverTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/OAuthMetadataResolver.swift BlueskyCore/Tests/BlueskyCoreTests/OAuthMetadataResolverTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
メッセージ例: `Add OAuth metadata resolver`

---

### Task 6: OAuthDiscovery（全体オーケストレーション）

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/OAuthDiscoveryTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthDiscovery.swift`

- [ ] **Step 1: 失敗するテストを書く（フルチェーンを 1 つの RoutingHTTPClient で）**

Create `BlueskyCore/Tests/BlueskyCoreTests/OAuthDiscoveryTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class OAuthDiscoveryTests: XCTestCase {
    func test_discover_resolvesHandleToFullAuthorizationServerMetadata() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social",
                body: #"{"did":"did:plc:abc123"}"#
            ),
            (
                url: "https://plc.directory/did:plc:abc123",
                body: #"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"#
            ),
            (
                url: "https://pds.example.com/.well-known/oauth-protected-resource",
                body: #"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#
            ),
            (
                url: "https://bsky.social/.well-known/oauth-authorization-server",
                body: #"{"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token","pushed_authorization_request_endpoint":"https://bsky.social/oauth/par"}"#
            )
        ])
        let discovery = OAuthDiscovery(http: http)

        let result = try await discovery.discover(account: "asonas.bsky.social")

        XCTAssertEqual(result.did, "did:plc:abc123")
        XCTAssertEqual(result.pds, URL(string: "https://pds.example.com"))
        XCTAssertEqual(result.authorizationServerIssuer, "https://bsky.social")
        XCTAssertEqual(result.metadata.authorizationEndpoint, "https://bsky.social/oauth/authorize")
        XCTAssertEqual(result.metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(result.metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }

    func test_discover_throwsWhenNoAuthorizationServerListed() async {
        let http = RoutingHTTPClient.json([
            (url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=h", body: #"{"did":"did:plc:abc123"}"#),
            (url: "https://plc.directory/did:plc:abc123", body: #"{"id":"did:plc:abc123","service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://pds.example.com"}]}"#),
            (url: "https://pds.example.com/.well-known/oauth-protected-resource", body: #"{"resource":"https://pds.example.com","authorization_servers":[]}"#)
        ])
        let discovery = OAuthDiscovery(http: http)
        do {
            _ = try await discovery.discover(account: "h")
            XCTFail("expected malformedDocument")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .malformedDocument("no authorization_servers listed"))
        }
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter OAuthDiscoveryTests`
Expected: FAIL（`OAuthDiscovery` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/OAuth/OAuthDiscovery.swift`:
```swift
import Foundation

/// Orchestrates the full OAuth discovery chain for an account:
/// handle/DID → DID → PDS → authorization server metadata.
public struct OAuthDiscovery: Sendable {
    /// The resolved endpoints needed to start an OAuth authorization for an account.
    public struct Result: Equatable, Sendable {
        public let did: String
        public let pds: URL
        public let authorizationServerIssuer: String
        public let metadata: AuthorizationServerMetadata
    }

    private let identity: IdentityResolver
    private let metadataResolver: OAuthMetadataResolver

    public init(http: HTTPClient) {
        self.identity = IdentityResolver(http: http)
        self.metadataResolver = OAuthMetadataResolver(http: http)
    }

    public init(identity: IdentityResolver, metadataResolver: OAuthMetadataResolver) {
        self.identity = identity
        self.metadataResolver = metadataResolver
    }

    public func discover(account handleOrDID: String) async throws -> Result {
        let did = try await identity.resolveHandleToDID(handleOrDID)
        let pds = try await identity.resolveDIDToPDS(did)
        let protectedResource = try await metadataResolver.protectedResource(pds: pds)
        guard let issuer = protectedResource.authorizationServers.first else {
            throw OAuthError.malformedDocument("no authorization_servers listed")
        }
        guard let issuerURL = URL(string: issuer) else {
            throw OAuthError.malformedDocument("invalid authorization server issuer: \(issuer)")
        }
        let metadata = try await metadataResolver.authorizationServer(issuer: issuerURL)
        return Result(
            did: did,
            pds: pds,
            authorizationServerIssuer: issuer,
            metadata: metadata
        )
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter OAuthDiscoveryTests`
Expected: PASS（2 テスト）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery add BlueskyCore/Sources/BlueskyCore/OAuth/OAuthDiscovery.swift BlueskyCore/Tests/BlueskyCoreTests/OAuthDiscoveryTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/oauth-discovery ai-commit
```
メッセージ例: `Add OAuthDiscovery orchestration`

---

### Task 7: 全テスト緑の確認と仕上げ

**Files:** なし（検証のみ）

- [ ] **Step 1: 全テストを実行**

Run: `swift test --package-path BlueskyCore`
Expected: 既存（BlueskyCore + HoshidukiyoKit）＋ 本プランの新規テストがすべて PASS。

- [ ] **Step 2: リリースビルド**

Run: `swift build --package-path BlueskyCore -c release`
Expected: 成功、警告なし。

- [ ] **Step 3: ブランチ仕上げ**

`superpowers:finishing-a-development-branch` に従い `feature/oauth-discovery` の取り込み方法を選ぶ。

---

## Self-Review

**1. Spec coverage:**
- §5.2 ステップ1（identity 解決: handle → DID → PDS）→ Task 3/4（`IdentityResolver`）。
- §5.2 ステップ2（authz server discovery: PDS → protected-resource → authorization-server メタデータ）→ Task 5（`OAuthMetadataResolver`）。
- 全体オーケストレーション → Task 6（`OAuthDiscovery`）。
- 本プラン対象外（後続）: PKCE・PAR・認可URL構築・トークン交換/リフレッシュ・`use_dpop_nonce` 再試行・`ASWebAuthenticationSession`・Keychain・`AccountManager`・アプリ結線。スコープ逸脱なし。

**2. Placeholder scan:** プレースホルダなし。各コードステップは完全なコードを含む。

**3. Type consistency:**
- `getDiscoveryJSON(_:http:decoder:)` は Task 3 定義、Task 3/4/5 で利用、戻り値の型推論で各モデルにデコード。
- `OAuthError`（`discoveryFailed`/`malformedDocument`/`pdsNotFound`/`unsupportedDIDMethod`）は Task 1 定義、Task 3/4/6 で送出、各テストで `Equatable` 比較。
- `DIDDocument`（`id`/`service`/`pdsEndpoint`）は Task 1、Task 4 の `resolveDIDToPDS` で利用。
- `ProtectedResourceMetadata.authorizationServers` / `AuthorizationServerMetadata`(`issuer`/`authorizationEndpoint`/`tokenEndpoint`/`pushedAuthorizationRequestEndpoint`) は Task 2 定義、Task 5/6 とテストで一致。
- `IdentityResolver(http:directory:plcDirectory:)`, `resolveHandleToDID(_:)`, `resolveDIDToPDS(_:)` は Task 3/4 で一致。
- `OAuthMetadataResolver(http:)`, `protectedResource(pds:)`, `authorizationServer(issuer:)` は Task 5/6 で一致。
- `OAuthDiscovery(http:)` / `OAuthDiscovery(identity:metadataResolver:)` / `discover(account:)` / `Result(did:pds:authorizationServerIssuer:metadata:)` は Task 6 とテストで一致。
- `RoutingHTTPClient`（`init(routes:)` / `static json(_:)` / `sentRequests`）は Task 3 定義、Task 3/4/5/6 のテストで一致。`HTTPRequest`/`HTTPResponse`/`HTTPClient`（Plan 1）を再利用。

## 次プラン（OAuth 認可: PKCE + PAR + 認可URL）への申し送り
- `OAuthDiscovery.Result` を入力に、PKCE（code_verifier/code_challenge=S256）と state を生成 → PAR（DPoP proof 付き、`use_dpop_nonce` 再試行）→ 認可URL構築、という流れを次プランで実装する。
- PKCE の code_challenge と DPoP の `ath` は両方 SHA-256 を使う。`DPoPCryptoProvider.sha256` を再利用するか、PKCE 用に乱数＋SHA-256 の小さな OS 抽象（`RandomBytesGenerator`）を足すかを次プラン冒頭で決める。
- `use_dpop_nonce` 再試行は PAR とトークン交換の両方で必要。レスポンスの `DPoP-Nonce` ヘッダを読む共通ラッパを設計する（`HTTPResponse.headers` から取得）。
- 本プランの discovery 結果（did / pds / token・authorize・PAR エンドポイント）はトークン交換・リフレッシュ・認証付き XRPC すべての前提になる。
