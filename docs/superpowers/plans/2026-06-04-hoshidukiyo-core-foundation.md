# Hoshidukiyo Core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `BlueskyCore` Swift Package の足場と、認証なしの XRPC 通信レイヤ（HTTP 抽象 + XRPC クライアント + エラーモデル）を、すべて単体テスト付きで構築する。

**Architecture:** UI 非依存のマルチプラットフォーム Swift Package。HTTP は `HTTPClient` プロトコルで抽象化し、テストはフェイク注入で実ネットワークなしに行う。XRPC クライアントは `baseURL/xrpc/<nsid>` に対する型付き GET/POST を提供し、非 2xx は `XRPCError` に変換する。Apple 実装の `URLSessionHTTPClient` を別ファイルに分離する。

**Tech Stack:** Swift 6 / Swift Package Manager / XCTest / Foundation（URLSession）。ターゲット macOS 14+ / iOS 17+。

このプランは設計書 `docs/superpowers/specs/2026-06-04-hoshidukiyo-design.md` の §4.2（OS 接点抽象: HTTP）・§4.3（`ATProtoHTTP` / `XRPCError`）に対応する。DPoP・OAuth・モデル・各 API は後続プランで積み増す。

## 前提・作業ルール

- リポジトリ: `/Users/asonas/workspace/hoshidukiyo`（既存。spec が main にコミット済み）
- 実装は **worktree で行う**。最初に次を実行する（ユーザーの git ルール）。
  ```bash
  git -C /Users/asonas/workspace/hoshidukiyo wt feature/core-foundation
  ```
  以降の作業はこの worktree 内で行う。
- コミットは **`/commit` スキル（`git ai-commit`）** を使う。`git commit` を直接実行しない。各 Task 末尾の「Commit」ステップは「対象ファイルを `git add` してから `git ai-commit` を実行する」を意味する。
- ビルド/テストは `cd` せず `--package-path` で行う。
  - ビルド: `swift build --package-path BlueskyCore`
  - テスト: `swift test --package-path BlueskyCore`
- 一度に複数テストを書かず、1テストずつ Red → Green → Refactor で進める。

## File Structure

作成するファイルと責務。

- `BlueskyCore/Package.swift` — パッケージ定義（library ターゲット `BlueskyCore` とテストターゲット `BlueskyCoreTests`）
- `BlueskyCore/Sources/BlueskyCore/Platform/HTTP.swift` — HTTP の値型（`HTTPMethod` / `HTTPRequest` / `HTTPResponse`）と `HTTPClient` プロトコル。OS 接点（HTTP）の抽象
- `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCError.swift` — `XRPCErrorResponse`（lexicon の `{error, message}`）と `XRPCError`
- `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift` — `baseURL/xrpc/<nsid>` への型付き GET/POST
- `BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift` — `HTTPClient` の Apple 実装（URLSession）
- `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift` — テスト用フェイク
- `BlueskyCore/Tests/BlueskyCoreTests/Support/URLProtocolStub.swift` — `URLSessionHTTPClient` 検証用の URLProtocol スタブ
- `BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift` — XRPC クライアントのテスト
- `BlueskyCore/Tests/BlueskyCoreTests/XRPCErrorTests.swift` — エラーモデルのテスト
- `BlueskyCore/Tests/BlueskyCoreTests/URLSessionHTTPClientTests.swift` — Apple 実装のテスト

---

### Task 1: Swift Package の足場

**Files:**
- Create: `BlueskyCore/Package.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/BlueskyCore.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/SmokeTests.swift`

- [ ] **Step 1: worktree を作成して移動**

Run:
```bash
git -C /Users/asonas/workspace/hoshidukiyo wt feature/core-foundation
```
作成された worktree ディレクトリ内で以降の作業を行う。

- [ ] **Step 2: `Package.swift` を作成**

Create `BlueskyCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueskyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BlueskyCore", targets: ["BlueskyCore"])
    ],
    targets: [
        .target(name: "BlueskyCore"),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"])
    ]
)
```

- [ ] **Step 3: ライブラリのプレースホルダ型を作成**

Create `BlueskyCore/Sources/BlueskyCore/BlueskyCore.swift`:
```swift
/// Marker for the BlueskyCore module. Real types live in their own files.
public enum BlueskyCore {
    /// Semantic version of the core module.
    public static let version = "0.0.1"
}
```

- [ ] **Step 4: スモークテストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class SmokeTests: XCTestCase {
    func test_moduleVersionIsExposed() {
        XCTAssertEqual(BlueskyCore.version, "0.0.1")
    }
}
```

- [ ] **Step 5: ビルドしてテストが通ることを確認**

Run: `swift test --package-path BlueskyCore`
Expected: `SmokeTests.test_moduleVersionIsExposed` が PASS。ビルドエラーなし。

- [ ] **Step 6: Commit**

```bash
git add BlueskyCore/Package.swift BlueskyCore/Sources BlueskyCore/Tests
```
その後 `/commit` スキル（`git ai-commit`）でコミット。メッセージ例: `Scaffold BlueskyCore Swift package`

---

### Task 2: HTTP の値型と `HTTPClient` プロトコル

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/HTTP.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift`（フェイク自体の挙動を SmokeTests とは別に検証）
- Create: `BlueskyCore/Tests/BlueskyCoreTests/HTTPClientTests.swift`

- [ ] **Step 1: HTTP の値型とプロトコルを作成**

Create `BlueskyCore/Sources/BlueskyCore/Platform/HTTP.swift`:
```swift
import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: HTTPMethod, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Abstraction over the platform HTTP stack. Apple ships `URLSessionHTTPClient`;
/// tests inject a fake. This is one of the six OS-touchpoint protocols in the design.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
```

- [ ] **Step 2: テスト用フェイクを作成**

Create `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift`:
```swift
import Foundation
@testable import BlueskyCore

/// Records sent requests and returns a canned response (or throws a canned error).
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    enum Outcome {
        case respond(HTTPResponse)
        case fail(Error)
    }

    var outcome: Outcome
    private(set) var sentRequests: [HTTPRequest] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    convenience init(response: HTTPResponse) {
        self.init(outcome: .respond(response))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        switch outcome {
        case .respond(let response):
            return response
        case .fail(let error):
            throw error
        }
    }
}
```

- [ ] **Step 3: フェイクの挙動テストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/HTTPClientTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class HTTPClientTests: XCTestCase {
    func test_fakeRecordsRequestAndReturnsStubbedResponse() async throws {
        let url = URL(string: "https://example.com/xrpc/test")!
        let fake = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Data("ok".utf8)))

        let response = try await fake.send(HTTPRequest(url: url, method: .get))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "ok")
        XCTAssertEqual(fake.sentRequests.count, 1)
        XCTAssertEqual(fake.sentRequests.first?.url, url)
        XCTAssertEqual(fake.sentRequests.first?.method, .get)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter HTTPClientTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add BlueskyCore/Sources/BlueskyCore/Platform/HTTP.swift BlueskyCore/Tests/BlueskyCoreTests/Support/FakeHTTPClient.swift BlueskyCore/Tests/BlueskyCoreTests/HTTPClientTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Add HTTP value types and HTTPClient protocol`

---

### Task 3: XRPC エラーモデル

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCError.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/XRPCErrorTests.swift`

- [ ] **Step 1: エラーモデルのデコードテストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/XRPCErrorTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class XRPCErrorTests: XCTestCase {
    func test_decodesErrorResponseWithMessage() throws {
        let json = Data(#"{"error":"InvalidRequest","message":"bad handle"}"#.utf8)

        let decoded = try JSONDecoder().decode(XRPCErrorResponse.self, from: json)

        XCTAssertEqual(decoded, XRPCErrorResponse(error: "InvalidRequest", message: "bad handle"))
    }

    func test_decodesErrorResponseWithoutMessage() throws {
        let json = Data(#"{"error":"ExpiredToken"}"#.utf8)

        let decoded = try JSONDecoder().decode(XRPCErrorResponse.self, from: json)

        XCTAssertEqual(decoded, XRPCErrorResponse(error: "ExpiredToken", message: nil))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCErrorTests`
Expected: FAIL（`XRPCErrorResponse` 未定義でビルドエラー）。

- [ ] **Step 3: エラーモデルを実装**

Create `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCError.swift`:
```swift
import Foundation

/// The body shape every XRPC endpoint returns on error: `{ "error": ..., "message"?: ... }`.
public struct XRPCErrorResponse: Decodable, Equatable, Sendable {
    public let error: String
    public let message: String?

    public init(error: String, message: String?) {
        self.error = error
        self.message = message
    }
}

/// Errors surfaced by `XRPCClient`.
public enum XRPCError: Error, Equatable {
    /// Non-2xx status. `body` is the decoded error payload when present.
    case requestFailed(status: Int, body: XRPCErrorResponse?)
    /// The success payload could not be decoded into the expected type.
    case decodingFailed(String)
    /// The endpoint NSID could not be turned into a valid URL.
    case invalidURL(String)
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCErrorTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add BlueskyCore/Sources/BlueskyCore/XRPC/XRPCError.swift BlueskyCore/Tests/BlueskyCoreTests/XRPCErrorTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Add XRPC error model`

---

### Task 4: `XRPCClient` の GET（成功パス）

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift`

- [ ] **Step 1: GET 成功のテストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class XRPCClientTests: XCTestCase {
    struct ResolveHandleResponse: Decodable, Equatable {
        let did: String
    }

    func test_get_buildsXrpcURLWithSortedQueryAndDecodesSuccess() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 200,
                body: Data(#"{"did":"did:plc:abc123"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        let result: ResolveHandleResponse = try await client.get(
            "com.atproto.identity.resolveHandle",
            parameters: ["handle": "asonas.bsky.social"]
        )

        XCTAssertEqual(result, ResolveHandleResponse(did: "did:plc:abc123"))
        XCTAssertEqual(
            fake.sentRequests.first?.url.absoluteString,
            "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=asonas.bsky.social"
        )
        XCTAssertEqual(fake.sentRequests.first?.method, .get)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCClientTests`
Expected: FAIL（`XRPCClient` 未定義でビルドエラー）。

- [ ] **Step 3: `XRPCClient` を実装（GET と内部デコード）**

Create `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift`:
```swift
import Foundation

/// Typed GET/POST against `baseURL/xrpc/<nsid>`. Unauthenticated for now;
/// auth headers and DPoP are layered on in a later plan.
public struct XRPCClient: Sendable {
    private let baseURL: URL
    private let http: HTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, http: HTTPClient) {
        self.baseURL = baseURL
        self.http = http
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func get<Response: Decodable>(
        _ nsid: String,
        parameters: [String: String] = [:]
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent("xrpc/\(nsid)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL(nsid)
        }
        if !parameters.isEmpty {
            components.queryItems = parameters
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw XRPCError.invalidURL(nsid)
        }
        let request = HTTPRequest(url: url, method: .get, headers: ["Accept": "application/json"])
        let response = try await http.send(request)
        return try decode(response)
    }

    private func decode<Response: Decodable>(_ response: HTTPResponse) throws -> Response {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? decoder.decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try decoder.decode(Response.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCClientTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Add XRPCClient GET with typed decoding`

---

### Task 5: `XRPCClient` の GET（エラーパス）

**Files:**
- Modify: `BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift`（テスト追加。実装は Task 4 の `decode` で既に対応済みのはずなので、これは振る舞いの固定化）

- [ ] **Step 1: 非 2xx でエラーを投げるテストを追加（失敗または成功を確認）**

`XRPCClientTests` クラスに以下のメソッドを追加:
```swift
    func test_get_throwsRequestFailedOnNon2xxWithDecodedBody() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 400,
                body: Data(#"{"error":"InvalidRequest","message":"bad handle"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        do {
            let _: ResolveHandleResponse = try await client.get(
                "com.atproto.identity.resolveHandle",
                parameters: ["handle": "nope"]
            )
            XCTFail("expected XRPCError.requestFailed")
        } catch let error as XRPCError {
            XCTAssertEqual(
                error,
                .requestFailed(
                    status: 400,
                    body: XRPCErrorResponse(error: "InvalidRequest", message: "bad handle")
                )
            )
        }
    }
```

- [ ] **Step 2: テストを実行**

Run: `swift test --package-path BlueskyCore --filter XRPCClientTests`
Expected: PASS（Task 4 の `decode` が非 2xx を処理済みのため）。万一 FAIL する場合は `decode` の分岐を見直す。

- [ ] **Step 3: Commit**

```bash
git add BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Cover XRPCClient non-2xx error path`

---

### Task 6: `XRPCClient` の POST

**Files:**
- Modify: `BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift`（`post` メソッド追加）
- Modify: `BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift`（POST テスト追加）

- [ ] **Step 1: POST のテストを追加（失敗させる）**

`XRPCClientTests` クラスに以下を追加:
```swift
    struct CreateSessionRequest: Encodable {
        let identifier: String
        let password: String
    }

    struct CreateSessionResponse: Decodable, Equatable {
        let accessJwt: String
        let did: String
    }

    func test_post_sendsJSONBodyToXrpcURLAndDecodesResponse() async throws {
        let fake = FakeHTTPClient(
            response: HTTPResponse(
                statusCode: 200,
                body: Data(#"{"accessJwt":"jwt-token","did":"did:plc:abc123"}"#.utf8)
            )
        )
        let client = XRPCClient(baseURL: URL(string: "https://bsky.social")!, http: fake)

        let result: CreateSessionResponse = try await client.post(
            "com.atproto.server.createSession",
            body: CreateSessionRequest(identifier: "asonas.bsky.social", password: "pw")
        )

        XCTAssertEqual(
            result,
            CreateSessionResponse(accessJwt: "jwt-token", did: "did:plc:abc123")
        )

        let sent = try XCTUnwrap(fake.sentRequests.first)
        XCTAssertEqual(
            sent.url.absoluteString,
            "https://bsky.social/xrpc/com.atproto.server.createSession"
        )
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")

        let sentBody = try XCTUnwrap(sent.body)
        let decodedBody = try JSONDecoder().decode(CreateSessionRequest.self, from: sentBody)
        XCTAssertEqual(decodedBody.identifier, "asonas.bsky.social")
        XCTAssertEqual(decodedBody.password, "pw")
    }
```
（`CreateSessionRequest` は `Decodable` も必要になるため、テストファイル内の定義を `struct CreateSessionRequest: Codable` に変更すること。）

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCClientTests`
Expected: FAIL（`post` 未定義でビルドエラー）。

- [ ] **Step 3: `post` を実装**

`XRPCClient` の `get(_:parameters:)` の直後に以下のメソッドを追加:
```swift
    public func post<Body: Encodable, Response: Decodable>(
        _ nsid: String,
        body: Body
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent("xrpc/\(nsid)")
        let payload = try encoder.encode(body)
        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: payload
        )
        let response = try await http.send(request)
        return try decode(response)
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter XRPCClientTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add BlueskyCore/Sources/BlueskyCore/XRPC/XRPCClient.swift BlueskyCore/Tests/BlueskyCoreTests/XRPCClientTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Add XRPCClient POST with JSON body`

---

### Task 7: Apple 実装 `URLSessionHTTPClient`

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/URLProtocolStub.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/URLSessionHTTPClientTests.swift`

- [ ] **Step 1: URLProtocol スタブを作成**

Create `BlueskyCore/Tests/BlueskyCoreTests/Support/URLProtocolStub.swift`:
```swift
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
```

- [ ] **Step 2: `URLSessionHTTPClient` のテストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/URLSessionHTTPClientTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class URLSessionHTTPClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func test_send_mapsRequestAndResponseThroughURLSession() async throws {
        URLProtocolStub.stub = (
            statusCode: 201,
            headers: ["X-Test": "yes"],
            body: Data("hello".utf8)
        )
        let client = URLSessionHTTPClient(session: makeSession())
        let url = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!

        let response = try await client.send(
            HTTPRequest(
                url: url,
                method: .post,
                headers: ["Content-Type": "application/json"],
                body: Data("{}".utf8)
            )
        )

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.headers["X-Test"], "yes")
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "hello")

        let captured = try XCTUnwrap(URLProtocolStub.capturedRequest)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
```

- [ ] **Step 3: テストが失敗することを確認**

Run: `swift test --package-path BlueskyCore --filter URLSessionHTTPClientTests`
Expected: FAIL（`URLSessionHTTPClient` 未定義でビルドエラー）。

- [ ] **Step 4: `URLSessionHTTPClient` を実装**

Create `BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift`:
```swift
import Foundation

/// Apple-platform `HTTPClient` backed by URLSession.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XRPCError.requestFailed(status: -1, body: nil)
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }

        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter URLSessionHTTPClientTests`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift BlueskyCore/Tests/BlueskyCoreTests/Support/URLProtocolStub.swift BlueskyCore/Tests/BlueskyCoreTests/URLSessionHTTPClientTests.swift
```
`/commit` スキルでコミット。メッセージ例: `Add URLSession-backed HTTPClient`

---

### Task 8: 全テスト緑の確認と仕上げ

**Files:**
- なし（検証のみ）

- [ ] **Step 1: 全テストを実行**

Run: `swift test --package-path BlueskyCore`
Expected: 全テスト PASS。`SmokeTests` / `HTTPClientTests` / `XRPCErrorTests` / `XRPCClientTests` / `URLSessionHTTPClientTests` がすべて緑。

- [ ] **Step 2: リリースビルドが通ることを確認**

Run: `swift build --package-path BlueskyCore -c release`
Expected: ビルド成功、警告なし。

- [ ] **Step 3: worktree をマージ（または PR 作成）**

`superpowers:finishing-a-development-branch` スキルに従って、`feature/core-foundation` の取り込み方法（マージ / PR / クリーンアップ）を選ぶ。

---

## Self-Review

**1. Spec coverage（本プランが対象とする範囲）:**
- §4.2 OS 接点抽象（HTTP）→ Task 2（`HTTPClient`）+ Task 7（`URLSessionHTTPClient`）でカバー。
- §4.3 `ATProtoHTTP`（XRPC トランスポート）→ Task 4/5/6（`XRPCClient`）でカバー。
- §4.3 `XRPCError`（`error`/`message`）→ Task 3 でカバー。
- §11 テスト戦略（`URLProtocol` スタブ / フェイク、実ネットワークなし）→ 全 Task でフェイク注入、Task 7 で URLProtocol スタブ。
- DPoP・OAuth・モデル・各 API・UI・Jetstream・通知は **本プランの対象外**（後続プラン 2〜10）。スコープ逸脱なし。

**2. Placeholder scan:** 「TBD」「後で実装」等のプレースホルダなし。各コードステップは完全なコードを含む。

**3. Type consistency:**
- `HTTPClient.send(_:)` のシグネチャは Task 2 定義と Task 7 実装・各テストで一致。
- `XRPCError` のケース（`requestFailed(status:body:)` / `decodingFailed` / `invalidURL`）は Task 3 定義、Task 4 `decode`、Task 5 テスト、Task 7 `URLSessionHTTPClient`（`-1` ケース）で一致。
- `XRPCErrorResponse(error:message:)` の初期化子は Task 3 定義とテストで一致。
- `XRPCClient.get(_:parameters:)` / `post(_:body:)` のシグネチャは定義とテストで一致。
- Task 6 の注記: `CreateSessionRequest` はリクエスト送信（Encodable）と送信ボディ検証のデコード（Decodable）の両方に使うため `Codable` にする旨を明記済み。
