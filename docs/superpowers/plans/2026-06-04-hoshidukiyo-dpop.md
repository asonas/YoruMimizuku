# Hoshidukiyo DPoP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `BlueskyCore` に DPoP（RFC 9449）proof 生成を追加する。純粋な proof 組み立てロジックは OS 非依存に保ち、鍵・署名・ハッシュは `DPoPCryptoProvider` プロトコルの背後に置く。Apple 実装は CryptoKit。

**Architecture:** OS 非依存の `DPoPProofBuilder` が、ヘッダ（`typ=dpop+jwt`, `alg=ES256`, 公開鍵 `jwk`）とクレーム（`htm`, `htu`, `iat`, `jti`, 任意で `ath`/`nonce`）を組み立て、base64url で連結した signing input を `DPoPCryptoProvider.signES256` で署名し、コンパクト JWT を返す。`DPoPCryptoProvider`（公開鍵 JWK / ES256 署名 / SHA-256）は OS 接点（crypto）の抽象で、テストはフェイク注入で決定論的に、Apple 実装は CryptoKit（P-256）で行う。最後に実鍵で「生成した proof の署名が公開鍵で検証できる」end-to-end テストを置く。

**Tech Stack:** Swift 6 / Swift Package Manager / XCTest / Foundation / CryptoKit（Apple 実装）。既存 `BlueskyCore`（macOS 14+/iOS 17+）に追加。

このプランは設計書 `docs/superpowers/specs/2026-06-04-hoshidukiyo-design.md` の §4.3（`DPoP`）・§4.2（OS 接点: 暗号・P-256 署名）・§5.3（DPoP の要点）に対応する。OAuth フロー本体・nonce 再試行のネットワーク統合・Keychain 永続化は後続プラン（Plan 3）で、本プランの `DPoPProofBuilder` と `DPoPCryptoProvider` を土台に積む。

## 前提・作業ルール

- リポジトリ: `/Users/asonas/workspace/hoshidukiyo`（main に Plan 1 がマージ済み）
- 実装は worktree で行う。最初に作成する：
  ```bash
  git -C /Users/asonas/workspace/hoshidukiyo wt feature/dpop
  ```
  作成される worktree は `/Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop`。以降の作業はこの中で行う。
- コミットは `git ai-commit`（`/commit` スキル）。`git commit` を直接実行しない。
- ビルド/テストは `cd` せず `--package-path` で：
  - `swift build --package-path BlueskyCore`
  - `swift test --package-path BlueskyCore`
- 1テストずつ Red → Green → Refactor。

## 背景知識（実装者向け、DPoP の要点）

- DPoP proof は ES256（ECDSA P-256 + SHA-256）で署名した JWT。
- ヘッダ: `{"typ":"dpop+jwt","alg":"ES256","jwk":{公開鍵}}`。`jwk` は EC P-256 公開鍵（`kty:"EC"`, `crv:"P-256"`, `x`, `y` は base64url の 32 バイト座標）。
- クレーム: `htm`（HTTP メソッド）, `htu`（リクエスト URI、**クエリとフラグメントを除く**）, `iat`（発行時刻・秒）, `jti`（一意な ID）。リソースにアクセストークンを添える場合は `ath`（base64url(SHA-256(access token)))、サーバから nonce を要求されたら `nonce`。
- signing input = `base64url(JSON(header))` + "." + `base64url(JSON(claims))`。これを ES256 署名し、署名を base64url 化して 3 つ目のセグメントにする。
- CryptoKit: `P256.Signing.PrivateKey().signature(for: data)` は SHA-256 でハッシュして署名し、`.rawRepresentation` が JOSE 形式の 64 バイト（r‖s）。公開鍵 `rawRepresentation` は 64 バイト（x‖y、先頭プレフィックスなし）。

## File Structure

- `BlueskyCore/Sources/BlueskyCore/DPoP/Base64URL.swift` — base64url のエンコード/デコード（内部ユーティリティ）
- `BlueskyCore/Sources/BlueskyCore/DPoP/ECPublicKeyJWK.swift` — EC P-256 公開鍵 JWK モデル（Codable）
- `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPCryptoProvider.swift` — crypto の OS 抽象プロトコル（公開鍵 JWK / ES256 署名 / SHA-256）
- `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPProofBuilder.swift` — OS 非依存の proof 組み立て
- `BlueskyCore/Sources/BlueskyCore/Platform/CryptoKitDPoPProvider.swift` — Apple 実装（CryptoKit / P-256）
- `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeDPoPCryptoProvider.swift` — テスト用フェイク
- `BlueskyCore/Tests/BlueskyCoreTests/Base64URLTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/CryptoKitDPoPProviderTests.swift`
- `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofIntegrationTests.swift`

---

### Task 1: Base64URL ユーティリティ

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Base64URLTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/DPoP/Base64URL.swift`

- [ ] **Step 0: worktree を作成**

Run: `git -C /Users/asonas/workspace/hoshidukiyo wt feature/dpop`
以降この worktree 内で作業（`swift test` の package path は worktree ルート基準）。

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/Base64URLTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class Base64URLTests: XCTestCase {
    func test_encode_usesURLAlphabetAndStripsPadding() {
        // 0xFB 0xFF produce '+' and '/' and padding in standard base64 ("+/8=").
        let data = Data([0xFB, 0xFF])
        XCTAssertEqual(Base64URL.encode(data), "-_8")
    }

    func test_decode_roundTripsArbitraryBytes() throws {
        let original = Data([0x00, 0x10, 0xFB, 0xFF, 0xA5, 0x7C])
        let encoded = Base64URL.encode(original)
        let decoded = try XCTUnwrap(Base64URL.decode(encoded))
        XCTAssertEqual(decoded, original)
    }

    func test_decode_returnsNilForInvalidInput() {
        XCTAssertNil(Base64URL.decode("!!!not base64!!!"))
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter Base64URLTests`
Expected: FAIL（`Base64URL` 未定義でビルドエラー）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/DPoP/Base64URL.swift`:
```swift
import Foundation

/// base64url (RFC 4648 §5) without padding, used for JWT segments and JWK coordinates.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter Base64URLTests`
Expected: PASS（3 テスト）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Sources/BlueskyCore/DPoP/Base64URL.swift BlueskyCore/Tests/BlueskyCoreTests/Base64URLTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
`git ai-commit` が使えない場合は中断して報告（`git commit` で代替しない）。メッセージ例: `Add base64url utility`

---

### Task 2: ECPublicKeyJWK モデルと DPoPCryptoProvider プロトコル（＋テスト用フェイク）

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/DPoP/ECPublicKeyJWK.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPCryptoProvider.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeDPoPCryptoProvider.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/DPoPCryptoProviderTests.swift`（フェイクとモデルの最小検証）

- [ ] **Step 1: モデルとプロトコルを実装**

Create `BlueskyCore/Sources/BlueskyCore/DPoP/ECPublicKeyJWK.swift`:
```swift
import Foundation

/// An EC P-256 public key in JWK form, as embedded in a DPoP proof header.
public struct ECPublicKeyJWK: Codable, Equatable, Sendable {
    public let kty: String
    public let crv: String
    public let x: String
    public let y: String

    public init(kty: String = "EC", crv: String = "P-256", x: String, y: String) {
        self.kty = kty
        self.crv = crv
        self.x = x
        self.y = y
    }
}
```

Create `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPCryptoProvider.swift`:
```swift
import Foundation

/// The cryptographic operations the DPoP layer needs, abstracted from the platform.
/// Apple ships `CryptoKitDPoPProvider`; tests inject a fake. This is the crypto
/// OS-touchpoint from the design (P-256 signing + hashing for DPoP).
public protocol DPoPCryptoProvider: Sendable {
    /// The provider's public key, as embedded in the DPoP proof header `jwk`.
    var publicKeyJWK: ECPublicKeyJWK { get }

    /// Sign `message` with ES256 (ECDSA P-256 + SHA-256). Returns the JOSE raw
    /// signature (64 bytes, r‖s).
    func signES256(_ message: Data) throws -> Data

    /// SHA-256 digest of `data` (used to compute the `ath` claim).
    func sha256(_ data: Data) -> Data
}
```

- [ ] **Step 2: テスト用フェイクを実装**

Create `BlueskyCore/Tests/BlueskyCoreTests/Support/FakeDPoPCryptoProvider.swift`:
```swift
import Foundation
@testable import BlueskyCore

/// Deterministic `DPoPCryptoProvider` for tests: fixed JWK, fixed signature,
/// and a fixed SHA-256 stand-in. No real crypto, so proof assembly can be
/// asserted byte-for-byte.
struct FakeDPoPCryptoProvider: DPoPCryptoProvider {
    var publicKeyJWK = ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y")
    var signature = Data([0xAA, 0xBB, 0xCC, 0xDD])
    var digest = Data([0x01, 0x02, 0x03, 0x04])

    func signES256(_ message: Data) throws -> Data { signature }
    func sha256(_ data: Data) -> Data { digest }
}
```

- [ ] **Step 3: 最小検証テストを書く（失敗させる）**

Create `BlueskyCore/Tests/BlueskyCoreTests/DPoPCryptoProviderTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class DPoPCryptoProviderTests: XCTestCase {
    func test_jwk_encodesECP256Fields() throws {
        let jwk = ECPublicKeyJWK(x: "abc", y: "def")
        let json = try JSONEncoder().encode(jwk)
        let object = try JSONSerialization.jsonObject(with: json) as? [String: String]

        XCTAssertEqual(object?["kty"], "EC")
        XCTAssertEqual(object?["crv"], "P-256")
        XCTAssertEqual(object?["x"], "abc")
        XCTAssertEqual(object?["y"], "def")
    }

    func test_fakeProvider_returnsConfiguredValues() throws {
        let fake = FakeDPoPCryptoProvider()
        XCTAssertEqual(fake.publicKeyJWK, ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y"))
        XCTAssertEqual(try fake.signES256(Data("anything".utf8)), Data([0xAA, 0xBB, 0xCC, 0xDD]))
        XCTAssertEqual(fake.sha256(Data("anything".utf8)), Data([0x01, 0x02, 0x03, 0x04]))
    }
}
```

- [ ] **Step 4: 失敗 → 実装済みなので通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DPoPCryptoProviderTests`
Expected: Step 1/2 を先に作る手順のため、テスト作成時点でビルドが通り PASS する。もし型名の不一致で FAIL したら Step 1/2 の定義と突き合わせて修正する。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Sources/BlueskyCore/DPoP/ECPublicKeyJWK.swift BlueskyCore/Sources/BlueskyCore/DPoP/DPoPCryptoProvider.swift BlueskyCore/Tests/BlueskyCoreTests/Support/FakeDPoPCryptoProvider.swift BlueskyCore/Tests/BlueskyCoreTests/DPoPCryptoProviderTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
メッセージ例: `Add EC JWK model and DPoP crypto provider protocol`

---

### Task 3: DPoPProofBuilder — 基本クレーム（ath/nonce なし）

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPProofBuilder.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift`:
```swift
import XCTest
@testable import BlueskyCore

final class DPoPProofBuilderTests: XCTestCase {
    // Decodes the three JWT segments for assertions.
    struct DecodedHeader: Decodable {
        let typ: String
        let alg: String
        let jwk: ECPublicKeyJWK
    }
    struct DecodedClaims: Decodable {
        let htm: String
        let htu: String
        let iat: Int
        let jti: String
        let ath: String?
        let nonce: String?
    }

    func decode<T: Decodable>(_ segment: Substring, as type: T.Type) throws -> T {
        let data = try XCTUnwrap(Base64URL.decode(String(segment)))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func makeBuilder() -> DPoPProofBuilder {
        DPoPProofBuilder(
            crypto: FakeDPoPCryptoProvider(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "fixed-jti" }
        )
    }

    func test_makeProof_buildsHeaderAndBaseClaims_withoutAthOrNonce() throws {
        let builder = makeBuilder()

        let proof = try builder.makeProof(
            method: .get,
            url: URL(string: "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=50")!
        )

        let segments = proof.split(separator: ".")
        XCTAssertEqual(segments.count, 3)

        let header = try decode(segments[0], as: DecodedHeader.self)
        XCTAssertEqual(header.typ, "dpop+jwt")
        XCTAssertEqual(header.alg, "ES256")
        XCTAssertEqual(header.jwk, ECPublicKeyJWK(x: "FAKE_X", y: "FAKE_Y"))

        let claims = try decode(segments[1], as: DecodedClaims.self)
        XCTAssertEqual(claims.htm, "GET")
        // htu drops the query string.
        XCTAssertEqual(claims.htu, "https://bsky.social/xrpc/app.bsky.feed.getTimeline")
        XCTAssertEqual(claims.iat, 1_700_000_000)
        XCTAssertEqual(claims.jti, "fixed-jti")
        XCTAssertNil(claims.ath)
        XCTAssertNil(claims.nonce)

        // The third segment is base64url(signature bytes from the provider).
        XCTAssertEqual(Base64URL.decode(String(segments[2])), Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter DPoPProofBuilderTests`
Expected: FAIL（`DPoPProofBuilder` 未定義でビルドエラー）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/DPoP/DPoPProofBuilder.swift`:
```swift
import Foundation

/// Builds DPoP proof JWTs (RFC 9449). OS-independent: all cryptography is
/// delegated to the injected `DPoPCryptoProvider`.
public struct DPoPProofBuilder: Sendable {
    private let crypto: DPoPCryptoProvider
    private let now: @Sendable () -> Date
    private let makeJTI: @Sendable () -> String

    public init(
        crypto: DPoPCryptoProvider,
        now: @escaping @Sendable () -> Date = { Date() },
        makeJTI: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.crypto = crypto
        self.now = now
        self.makeJTI = makeJTI
    }

    /// Build a compact DPoP proof for the given request. Pass `accessToken` to
    /// include the `ath` claim, and `nonce` when the server demands one.
    public func makeProof(
        method: HTTPMethod,
        url: URL,
        accessToken: String? = nil,
        nonce: String? = nil
    ) throws -> String {
        let header = Header(jwk: crypto.publicKeyJWK)
        let ath = accessToken.map { Base64URL.encode(crypto.sha256(Data($0.utf8))) }
        let claims = Claims(
            htm: method.rawValue,
            htu: Self.htu(from: url),
            iat: Int(now().timeIntervalSince1970),
            jti: makeJTI(),
            ath: ath,
            nonce: nonce
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let headerSegment = Base64URL.encode(try encoder.encode(header))
        let claimsSegment = Base64URL.encode(try encoder.encode(claims))
        let signingInput = headerSegment + "." + claimsSegment
        let signature = try crypto.signES256(Data(signingInput.utf8))
        return signingInput + "." + Base64URL.encode(signature)
    }

    /// The `htu` claim is the request URI with query and fragment removed.
    static func htu(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    private struct Header: Encodable {
        let typ = "dpop+jwt"
        let alg = "ES256"
        let jwk: ECPublicKeyJWK
    }

    private struct Claims: Encodable {
        let htm: String
        let htu: String
        let iat: Int
        let jti: String
        let ath: String?
        let nonce: String?

        enum CodingKeys: String, CodingKey {
            case htm, htu, iat, jti, ath, nonce
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(htm, forKey: .htm)
            try container.encode(htu, forKey: .htu)
            try container.encode(iat, forKey: .iat)
            try container.encode(jti, forKey: .jti)
            try container.encodeIfPresent(ath, forKey: .ath)
            try container.encodeIfPresent(nonce, forKey: .nonce)
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DPoPProofBuilderTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Sources/BlueskyCore/DPoP/DPoPProofBuilder.swift BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
メッセージ例: `Add DPoPProofBuilder with base claims`

---

### Task 4: DPoPProofBuilder — ath と nonce

**Files:**
- Modify: `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift`（テスト追加。実装は Task 3 で対応済み）

- [ ] **Step 1: ath/nonce のテストを追加**

`DPoPProofBuilderTests` クラスに以下を追加（`decode`/`makeBuilder`/`DecodedClaims` は既存を再利用）:
```swift
    func test_makeProof_includesAthFromAccessTokenAndNonce() throws {
        let builder = makeBuilder()

        let proof = try builder.makeProof(
            method: .post,
            url: URL(string: "https://bsky.social/xrpc/com.atproto.repo.createRecord")!,
            accessToken: "access-token-123",
            nonce: "server-nonce-xyz"
        )

        let segments = proof.split(separator: ".")
        let claims = try decode(segments[1], as: DecodedClaims.self)

        XCTAssertEqual(claims.htm, "POST")
        XCTAssertEqual(claims.htu, "https://bsky.social/xrpc/com.atproto.repo.createRecord")
        // ath == base64url(provider.sha256(token)); the fake digest is fixed bytes.
        XCTAssertEqual(claims.ath, Base64URL.encode(Data([0x01, 0x02, 0x03, 0x04])))
        XCTAssertEqual(claims.nonce, "server-nonce-xyz")
    }
```

- [ ] **Step 2: テストを実行**

Run: `swift test --package-path BlueskyCore --filter DPoPProofBuilderTests`
Expected: PASS（Task 3 の実装が ath/nonce を処理済み）。FAIL する場合は `makeProof` の ath/nonce 分岐を見直し、テストは書き換えない。

- [ ] **Step 3: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Tests/BlueskyCoreTests/DPoPProofBuilderTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
メッセージ例: `Cover DPoP proof ath and nonce claims`

---

### Task 5: CryptoKitDPoPProvider（Apple 実装）

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/CryptoKitDPoPProviderTests.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/CryptoKitDPoPProvider.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/CryptoKitDPoPProviderTests.swift`:
```swift
import XCTest
import CryptoKit
@testable import BlueskyCore

final class CryptoKitDPoPProviderTests: XCTestCase {
    func test_publicKeyJWK_hasP256FieldsWith32ByteCoordinates() throws {
        let provider = CryptoKitDPoPProvider()
        let jwk = provider.publicKeyJWK

        XCTAssertEqual(jwk.kty, "EC")
        XCTAssertEqual(jwk.crv, "P-256")
        XCTAssertEqual(try XCTUnwrap(Base64URL.decode(jwk.x)).count, 32)
        XCTAssertEqual(try XCTUnwrap(Base64URL.decode(jwk.y)).count, 32)
    }

    func test_signES256_producesSignatureThatVerifiesWithPublicKey() throws {
        let key = P256.Signing.PrivateKey()
        let provider = CryptoKitDPoPProvider(privateKey: key)
        let message = Data("message to sign".utf8)

        let rawSignature = try provider.signES256(message)
        XCTAssertEqual(rawSignature.count, 64)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: message))
    }

    func test_sha256_matchesCryptoKit() {
        let provider = CryptoKitDPoPProvider()
        let data = Data("hash me".utf8)

        let expected = Data(SHA256.hash(data: data))
        XCTAssertEqual(provider.sha256(data), expected)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter CryptoKitDPoPProviderTests`
Expected: FAIL（`CryptoKitDPoPProvider` 未定義でビルドエラー）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/BlueskyCore/Platform/CryptoKitDPoPProvider.swift`:
```swift
import Foundation
import CryptoKit

/// Apple-platform `DPoPCryptoProvider` backed by CryptoKit's P-256.
public struct CryptoKitDPoPProvider: DPoPCryptoProvider {
    private let privateKey: P256.Signing.PrivateKey

    /// Generate a fresh P-256 key.
    public init() {
        self.privateKey = P256.Signing.PrivateKey()
    }

    /// Wrap an existing key (e.g. one restored from the Keychain in a later plan).
    public init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public var publicKeyJWK: ECPublicKeyJWK {
        // rawRepresentation is the 64-byte uncompressed point (x‖y), no prefix.
        let raw = privateKey.publicKey.rawRepresentation
        let x = raw.prefix(32)
        let y = raw.suffix(32)
        return ECPublicKeyJWK(x: Base64URL.encode(Data(x)), y: Base64URL.encode(Data(y)))
    }

    public func signES256(_ message: Data) throws -> Data {
        // signature(for:) hashes with SHA-256 (ES256) and rawRepresentation is JOSE r‖s.
        try privateKey.signature(for: message).rawRepresentation
    }

    public func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter CryptoKitDPoPProviderTests`
Expected: PASS（3 テスト）。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Sources/BlueskyCore/Platform/CryptoKitDPoPProvider.swift BlueskyCore/Tests/BlueskyCoreTests/CryptoKitDPoPProviderTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
メッセージ例: `Add CryptoKit-backed DPoP crypto provider`

---

### Task 6: 統合テスト（実鍵で proof 署名が検証できる）

**Files:**
- Create: `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofIntegrationTests.swift`

- [ ] **Step 1: end-to-end テストを書く**

Create `BlueskyCore/Tests/BlueskyCoreTests/DPoPProofIntegrationTests.swift`:
```swift
import XCTest
import CryptoKit
@testable import BlueskyCore

final class DPoPProofIntegrationTests: XCTestCase {
    struct DecodedHeader: Decodable {
        let jwk: ECPublicKeyJWK
    }

    func test_realProvider_proofSignatureVerifiesAgainstEmbeddedJWK() throws {
        let provider = CryptoKitDPoPProvider()
        let builder = DPoPProofBuilder(
            crypto: provider,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeJTI: { "integration-jti" }
        )

        let proof = try builder.makeProof(
            method: .post,
            url: URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!,
            accessToken: "an-access-token",
            nonce: "a-nonce"
        )

        let segments = proof.split(separator: ".")
        XCTAssertEqual(segments.count, 3)

        // Reconstruct the public key from the embedded JWK and verify the signature
        // over the signing input (header.claims).
        let headerData = try XCTUnwrap(Base64URL.decode(String(segments[0])))
        let header = try JSONDecoder().decode(DecodedHeader.self, from: headerData)
        let x = try XCTUnwrap(Base64URL.decode(header.jwk.x))
        let y = try XCTUnwrap(Base64URL.decode(header.jwk.y))
        let publicKey = try P256.Signing.PublicKey(rawRepresentation: x + y)

        let signingInput = Data((String(segments[0]) + "." + String(segments[1])).utf8)
        let signatureData = try XCTUnwrap(Base64URL.decode(String(segments[2])))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: signingInput))
    }
}
```

- [ ] **Step 2: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DPoPProofIntegrationTests`
Expected: PASS。これは `DPoPProofBuilder` と `CryptoKitDPoPProvider` の結合が DPoP 仕様どおりに動くことの最終的な裏付け。

- [ ] **Step 3: Commit**

```bash
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop add BlueskyCore/Tests/BlueskyCoreTests/DPoPProofIntegrationTests.swift
git -C /Users/asonas/workspace/hoshidukiyo/.worktrees/feature/dpop ai-commit
```
メッセージ例: `Verify DPoP proof signature end to end`

---

### Task 7: 全テスト緑の確認と仕上げ

**Files:** なし（検証のみ）

- [ ] **Step 1: 全テストを実行**

Run: `swift test --package-path BlueskyCore`
Expected: 既存 8 テスト ＋ 本プランの新規テストがすべて PASS。

- [ ] **Step 2: リリースビルド**

Run: `swift build --package-path BlueskyCore -c release`
Expected: 成功、警告なし。

- [ ] **Step 3: ブランチ仕上げ**

`superpowers:finishing-a-development-branch` に従い `feature/dpop` の取り込み方法を選ぶ。

---

## Self-Review

**1. Spec coverage:**
- §4.3 `DPoP`（proof 生成）→ Task 3/4（`DPoPProofBuilder`）。
- §4.2 OS 接点（crypto・P-256 署名）→ Task 2（`DPoPCryptoProvider` 抽象）＋ Task 5（`CryptoKitDPoPProvider`）。
- §5.3 DPoP の要点（`typ`/`alg`/`jwk`、`htm`/`htu`/`iat`/`jti`/`ath`/`nonce`、ES256、ath=SHA-256）→ Task 3/4/5/6 で全項目を実装・検証。base64url は Task 1。
- 本プラン対象外（後続）: OAuth フロー本体、`use_dpop_nonce` のネットワーク再試行統合（Plan 3）、Keychain への鍵永続化（Plan 3）。スコープ逸脱なし。

**2. Placeholder scan:** プレースホルダなし。各コードステップは完全なコードを含む。

**3. Type consistency:**
- `DPoPCryptoProvider`（`publicKeyJWK`/`signES256`/`sha256`）は Task 2 定義、Task 3 利用（`crypto.publicKeyJWK`/`crypto.signES256`/`crypto.sha256`）、Task 5 Apple 実装、Task 2/5 テストのフェイク/実装で一致。
- `ECPublicKeyJWK(kty:crv:x:y:)`（既定 `kty="EC"`,`crv="P-256"`）は Task 2 定義と全テストで一致。
- `DPoPProofBuilder(crypto:now:makeJTI:)` と `makeProof(method:url:accessToken:nonce:)` は Task 3 定義、Task 3/4/6 テストで一致。`method` は既存 `HTTPMethod`（`.get`/`.post`、rawValue=GET/POST）を再利用。
- `Base64URL.encode/decode` は Task 1 定義、Task 3/5/6 とテストで一致。
- 署名形式の整合: `CryptoKitDPoPProvider.signES256` は 64 バイト raw（r‖s）を返し、Task 6 は `P256.Signing.ECDSASignature(rawRepresentation:)` で復元して検証する（一致）。

## 次プラン（Plan 3: OAuth）への申し送り
- Plan 1 最終レビュー由来: transport エラー（`HTTPClientError`）と `XRPCError` は現状兄弟関係。Plan 3 で `use_dpop_nonce`（401 + `DPoP-Nonce` ヘッダ）の再試行を XRPC 層に統合する際、nonce 要求の検出をどちらのエラー空間で表現するかを冒頭で確定する。
- `DPoPProofBuilder` の `makeJTI` 既定は `UUID().uuidString`。OAuth 統合時に jti の一意性要件（リプレイ防止）を満たすことを確認する。
- 鍵の永続化（Keychain への P-256 秘密鍵の保存/復元）は Plan 3 で `CryptoKitDPoPProvider(privateKey:)` を使って行う。`P256.Signing.PrivateKey` は `rawRepresentation`/`init(rawRepresentation:)` で 32 バイト保存・復元可能。
