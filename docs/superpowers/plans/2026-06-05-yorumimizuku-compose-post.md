# 投稿機能（コンポーザ）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アプリから Bluesky に投稿（URL/ハッシュタグ/メンションの facet・最大4枚の画像・リプライ）できるようにする。

**Architecture:** 純粋ロジック `FacetDetector`（link/tag/mention候補をUTF-8バイトオフセットで検出）を core に置き、`PostService` が mention を `getProfile` でDID解決して facet を完成、`uploadBlob`→`createRecord` を DPoP 経由で送る。UI は `ComposerViewModel`（YoruMimizukuKit）＋ `ComposerView`（シート、apps/macos）。

**Tech Stack:** Swift 6.0 / strict concurrency, SwiftPM (`core/`), XCTest, XcodeGen, SwiftUI。既存の `DPoPRequestSender` / `OAuthMetadataResolver` / `TokenService` パターンを踏襲。

作業ディレクトリ: `.worktrees/feature/compose-post`。テストは `cd core && swift test`。

---

## ファイル構成

- Create: `core/Sources/BlueskyCore/RichText/FacetDetector.swift` — link/tag/mention候補の検出（純粋）
- Modify: `core/Sources/BlueskyCore/Models/Timeline.swift` — `FacetFeature` に `Encodable` 追加
- Create: `core/Sources/BlueskyCore/Models/PostWrite.swift` — 送信用 Encodable（`PostRecordWrite`/`FacetWrite`/`ImagesEmbedWrite`/`ImageWrite`/`ReplyRefWrite`/`StrongRef`）と `BlobRef`、レスポンス（`UploadBlobResponse`/`CreateRecordResponse`/`GetRecordResponse`/`ResolveDIDResponse`）
- Create: `core/Sources/BlueskyCore/XRPC/PostService.swift` — `uploadBlob` / `createPost`
- Create: `core/Sources/YoruMimizukuKit/PostDraft.swift` — `PostDraft` / `ComposeImage` / `PostResult`
- Create: `core/Sources/YoruMimizukuKit/PostSubmitting.swift` — protocol
- Create: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift` — 入力/文字数/送信状態
- Create: `core/Tests/BlueskyCoreTests/FacetDetectorTests.swift`
- Create: `core/Tests/BlueskyCoreTests/PostWriteTests.swift`
- Create: `core/Tests/BlueskyCoreTests/PostServiceTests.swift`
- Create: `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift`
- Create: `apps/macos/Compose/LiveComposer.swift` — `PostSubmitting` 実装（`LiveServiceContext` 経由）
- Create: `apps/macos/Views/ComposerView.swift` — シートUI
- Modify: `apps/macos/Views/MainWindowView.swift` — `n` キーで新規コンポーザ、シート提示
- Modify: `apps/macos/Views/PostRowView.swift` / `ConversationView.swift` — 返信導線（必要に応じて）

---

## Task 1: FacetDetector — link 検出

**Files:**
- Create: `core/Sources/BlueskyCore/RichText/FacetDetector.swift`
- Test: `core/Tests/BlueskyCoreTests/FacetDetectorTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import BlueskyCore

final class FacetDetectorTests: XCTestCase {
    func testDetectsBareLinkWithByteOffsets() {
        let text = "see https://example.com now"
        let facets = FacetDetector.detect(text: text)
        XCTAssertEqual(facets.count, 1)
        let f = facets[0]
        XCTAssertEqual(f.byteStart, 4)
        XCTAssertEqual(f.byteEnd, 23)
        XCTAssertEqual(f.feature, .link(uri: "https://example.com"))
    }

    func testTrimsTrailingPunctuationFromLink() {
        let text = "(https://example.com/path)."
        let facets = FacetDetector.detect(text: text)
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .link(uri: "https://example.com/path"))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: コンパイルエラー（`FacetDetector` 未定義）

- [ ] **Step 3: 最小実装**

```swift
import Foundation

/// Detects rich-text facets in post text using UTF-8 byte offsets (NOT character
/// offsets), mirroring the proven detection in tempest. `link` and `tag` are
/// produced complete; `mentionCandidate` carries the `@handle` range and handle
/// string for `PostService` to resolve to a DID. Mirrors the display-side
/// `RichText` decoder so composed and rendered facets stay symmetric.
public enum FacetDetector {
    public struct DetectedFacet: Equatable, Sendable {
        public let byteStart: Int
        public let byteEnd: Int
        public let feature: Feature

        public init(byteStart: Int, byteEnd: Int, feature: Feature) {
            self.byteStart = byteStart
            self.byteEnd = byteEnd
            self.feature = feature
        }
    }

    public enum Feature: Equatable, Sendable {
        case link(uri: String)
        case tag(tag: String)
        case mentionCandidate(handle: String)
    }

    /// Detect all facets and return them sorted by byte start.
    public static func detect(text: String) -> [DetectedFacet] {
        let all = detectLinks(text)
        return all.sorted { $0.byteStart < $1.byteStart }
    }

    // Trailing characters stripped from a detected URL so a sentence's closing
    // punctuation does not become part of the link (mirrors @atproto/api).
    private static let linkTrailing = CharacterSet(charactersIn: ".,;:!?)\"']")

    static func detectLinks(_ text: String) -> [DetectedFacet] {
        let bytes = Array(text.utf8)
        var facets: [DetectedFacet] = []
        // Scan for http(s):// runs up to the next whitespace.
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+") else { return [] }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var uri = ns.substring(with: match.range)
            // Strip trailing punctuation; keep a closing paren only if the URL has a matching open paren.
            while let last = uri.unicodeScalars.last, linkTrailing.contains(last) {
                if last == ")" && uri.filter({ $0 == "(" }).count > uri.filter({ $0 == ")" }).count { break }
                uri = String(uri.dropLast())
            }
            guard !uri.isEmpty else { continue }
            let uriBytes = Array(uri.utf8)
            // Locate the URL's byte range by re-finding its byte prefix from the match's UTF-16 start.
            let prefix = ns.substring(to: match.range.location)
            let byteStart = Array(prefix.utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteStart + uriBytes.count,
                                        feature: .link(uri: uri)))
        }
        return facets
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/RichText/FacetDetector.swift core/Tests/BlueskyCoreTests/FacetDetectorTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add FacetDetector with link detection (UTF-8 byte offsets, trailing punctuation trim)"
```

---

## Task 2: FacetDetector — tag 検出

**Files:**
- Modify: `core/Sources/BlueskyCore/RichText/FacetDetector.swift`
- Test: `core/Tests/BlueskyCoreTests/FacetDetectorTests.swift`

- [ ] **Step 1: 失敗するテストを追加**

```swift
extension FacetDetectorTests {
    func testDetectsHashtag() {
        let facets = FacetDetector.detect(text: "hello #swift world")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .tag(tag: "swift"))
        XCTAssertEqual(facets[0].byteStart, 6)
        XCTAssertEqual(facets[0].byteEnd, 12)
    }

    func testIgnoresNumericOnlyHashtag() {
        XCTAssertTrue(FacetDetector.detect(text: "code #123 here").isEmpty)
    }

    func testHashtagByteOffsetsWithMultibytePrefix() {
        // "あ" is 3 UTF-8 bytes; the tag starts after it plus a space.
        let facets = FacetDetector.detect(text: "あ #tag")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .tag(tag: "tag"))
        XCTAssertEqual(facets[0].byteStart, 4)
        XCTAssertEqual(facets[0].byteEnd, 8)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: FAIL（tag が検出されない / `detect` が link のみ）

- [ ] **Step 3: 実装（`detect` に tag を統合し、tag 検出を追加）**

`detect(text:)` を差し替え:

```swift
    public static func detect(text: String) -> [DetectedFacet] {
        let all = detectLinks(text) + detectTags(text)
        return all.sorted { $0.byteStart < $1.byteStart }
    }
```

`FacetDetector` に追加:

```swift
    // A hashtag starts at text start or after whitespace, allows a fullwidth '#',
    // must contain at least one non-digit/non-punctuation character (so bare
    // "#123" is ignored), drops trailing punctuation, and is capped at 64 graphemes.
    static func detectTags(_ text: String) -> [DetectedFacet] {
        guard text.contains("#") || text.contains("＃") else { return [] }
        let pattern = "(?:^|\\s)[#＃]([^\\s#＃]*[^\\d\\s\\p{P}#＃]+[^\\s#＃]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var facets: [DetectedFacet] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let bodyRange = match.range(at: 1)
            var tag = ns.substring(with: bodyRange)
            while let last = tag.unicodeScalars.last,
                  CharacterSet.punctuationCharacters.contains(last) {
                tag = String(tag.dropLast())
            }
            guard !tag.isEmpty, tag.count <= 64 else { continue }
            // The '#' sits one UTF-16 unit before the captured body; rebuild byte offsets.
            let hashUTF16 = bodyRange.location - 1
            let prefix = ns.substring(to: hashUTF16)
            let byteStart = Array(prefix.utf8).count
            let byteEnd = byteStart + Array(("#" + tag).utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteEnd, feature: .tag(tag: tag)))
        }
        return facets
    }
```

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/RichText/FacetDetector.swift core/Tests/BlueskyCoreTests/FacetDetectorTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add hashtag (tag) facet detection to FacetDetector"
```

---

## Task 3: FacetDetector — mention 候補検出

**Files:**
- Modify: `core/Sources/BlueskyCore/RichText/FacetDetector.swift`
- Test: `core/Tests/BlueskyCoreTests/FacetDetectorTests.swift`

- [ ] **Step 1: 失敗するテストを追加**

```swift
extension FacetDetectorTests {
    func testDetectsMentionCandidate() {
        let facets = FacetDetector.detect(text: "hi @alice.bsky.social !")
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].feature, .mentionCandidate(handle: "alice.bsky.social"))
        XCTAssertEqual(facets[0].byteStart, 3)
        XCTAssertEqual(facets[0].byteEnd, 21)
    }

    func testSortsMixedFacetsByByteStart() {
        let facets = FacetDetector.detect(text: "@bob.test #tag https://x.io")
        XCTAssertEqual(facets.map(\.feature), [
            .mentionCandidate(handle: "bob.test"),
            .tag(tag: "tag"),
            .link(uri: "https://x.io"),
        ])
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: FAIL

- [ ] **Step 3: 実装（`detect` に mention を統合し検出を追加）**

`detect(text:)` を差し替え:

```swift
    public static func detect(text: String) -> [DetectedFacet] {
        let all = detectLinks(text) + detectTags(text) + detectMentions(text)
        return all.sorted { $0.byteStart < $1.byteStart }
    }
```

追加:

```swift
    // A mention starts at text start or after whitespace / '(' / '[' and matches a
    // domain-shaped handle. The byte range covers '@' + handle; PostService resolves
    // the handle to a DID and drops the facet when resolution fails.
    static func detectMentions(_ text: String) -> [DetectedFacet] {
        guard text.contains("@") else { return [] }
        let pattern = "(?:^|[\\s(\\[])@([a-zA-Z0-9._-]+\\.[a-zA-Z]{2,})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var facets: [DetectedFacet] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let handleRange = match.range(at: 1)
            let handle = ns.substring(with: handleRange)
            let atUTF16 = handleRange.location - 1
            let prefix = ns.substring(to: atUTF16)
            let byteStart = Array(prefix.utf8).count
            let byteEnd = byteStart + Array(("@" + handle).utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteEnd,
                                        feature: .mentionCandidate(handle: handle)))
        }
        return facets
    }
```

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter FacetDetectorTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/RichText/FacetDetector.swift core/Tests/BlueskyCoreTests/FacetDetectorTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add mention-candidate facet detection to FacetDetector"
```

---

## Task 4: 送信用モデルのエンコード/デコード

**Files:**
- Modify: `core/Sources/BlueskyCore/Models/Timeline.swift:198-227`（`FacetFeature` に `Encodable`）
- Create: `core/Sources/BlueskyCore/Models/PostWrite.swift`
- Test: `core/Tests/BlueskyCoreTests/PostWriteTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import BlueskyCore

final class PostWriteTests: XCTestCase {
    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFacetWriteEncodesIndexAndLinkFeature() throws {
        let facet = FacetWrite(byteStart: 4, byteEnd: 23, feature: .link(uri: "https://example.com"))
        let json = try encodeJSON(facet)
        let index = try XCTUnwrap(json["index"] as? [String: Any])
        XCTAssertEqual(index["byteStart"] as? Int, 4)
        XCTAssertEqual(index["byteEnd"] as? Int, 23)
        let features = try XCTUnwrap(json["features"] as? [[String: Any]])
        XCTAssertEqual(features.first?["$type"] as? String, "app.bsky.richtext.facet#link")
        XCTAssertEqual(features.first?["uri"] as? String, "https://example.com")
    }

    func testPostRecordWriteEncodesTypeAndOmitsEmptyFacets() throws {
        let record = PostRecordWrite(text: "hi", createdAt: "2026-06-05T00:00:00.000Z",
                                     facets: [], embed: nil, reply: nil)
        let json = try encodeJSON(record)
        XCTAssertEqual(json["$type"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(json["text"] as? String, "hi")
        XCTAssertNil(json["facets"])
        XCTAssertNil(json["embed"])
        XCTAssertNil(json["reply"])
    }

    func testImagesEmbedEncodesBlobRef() throws {
        let blob = BlobRef(cid: "bafycid", mimeType: "image/jpeg", size: 1234)
        let embed = ImagesEmbedWrite(images: [ImageWrite(image: blob, alt: "a cat")])
        let json = try encodeJSON(embed)
        XCTAssertEqual(json["$type"] as? String, "app.bsky.embed.images")
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.first?["alt"] as? String, "a cat")
        let image = try XCTUnwrap(images.first?["image"] as? [String: Any])
        XCTAssertEqual(image["$type"] as? String, "blob")
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(image["size"] as? Int, 1234)
        let ref = try XCTUnwrap(image["ref"] as? [String: Any])
        XCTAssertEqual(ref["$link"] as? String, "bafycid")
    }

    func testUploadBlobResponseDecodes() throws {
        let data = Data(##"""
        {"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/png","size":42}}
        """##.utf8)
        let decoded = try JSONDecoder().decode(UploadBlobResponse.self, from: data)
        XCTAssertEqual(decoded.blob.cid, "bafycid")
        XCTAssertEqual(decoded.blob.mimeType, "image/png")
        XCTAssertEqual(decoded.blob.size, 42)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter PostWriteTests`
Expected: コンパイルエラー（型未定義）

- [ ] **Step 3: 実装**

`core/Sources/BlueskyCore/Models/Timeline.swift` の `FacetFeature` 宣言を `Decodable` から `Codable` に変更し、`init(from:)` の後に `encode(to:)` を追加:

```swift
public enum FacetFeature: Codable, Equatable, Sendable {
```

`init(from decoder:)` の閉じ括弧の直後（enum 内）に追加:

```swift
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .link(let uri):
            try container.encode("app.bsky.richtext.facet#link", forKey: .type)
            try container.encode(uri, forKey: .uri)
        case .mention(let did):
            try container.encode("app.bsky.richtext.facet#mention", forKey: .type)
            try container.encode(did, forKey: .did)
        case .tag(let tag):
            try container.encode("app.bsky.richtext.facet#tag", forKey: .type)
            try container.encode(tag, forKey: .tag)
        }
    }
```

新規 `core/Sources/BlueskyCore/Models/PostWrite.swift`:

```swift
import Foundation

/// A blob reference (`blob`) returned by `com.atproto.repo.uploadBlob` and embedded
/// back into a record. JSON shape: `{ "$type":"blob", "ref":{"$link":<cid>},
/// "mimeType":..., "size":... }`.
public struct BlobRef: Codable, Equatable, Sendable {
    public let cid: String
    public let mimeType: String
    public let size: Int

    public init(cid: String, mimeType: String, size: Int) {
        self.cid = cid
        self.mimeType = mimeType
        self.size = size
    }

    enum CodingKeys: String, CodingKey { case type = "$type", ref, mimeType, size }
    enum RefKeys: String, CodingKey { case link = "$link" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ref = try c.nestedContainer(keyedBy: RefKeys.self, forKey: .ref)
        self.cid = try ref.decode(String.self, forKey: .link)
        self.mimeType = try c.decode(String.self, forKey: .mimeType)
        self.size = try c.decode(Int.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("blob", forKey: .type)
        var ref = c.nestedContainer(keyedBy: RefKeys.self, forKey: .ref)
        try ref.encode(cid, forKey: .link)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(size, forKey: .size)
    }
}

/// One rich-text facet for a record write. Encodes to `{ "index":{byteStart,byteEnd},
/// "features":[<feature>] }`.
public struct FacetWrite: Encodable, Equatable, Sendable {
    public let byteStart: Int
    public let byteEnd: Int
    public let feature: FacetFeature

    public init(byteStart: Int, byteEnd: Int, feature: FacetFeature) {
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.feature = feature
    }

    enum CodingKeys: String, CodingKey { case index, features }
    enum IndexKeys: String, CodingKey { case byteStart, byteEnd }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var index = c.nestedContainer(keyedBy: IndexKeys.self, forKey: .index)
        try index.encode(byteStart, forKey: .byteStart)
        try index.encode(byteEnd, forKey: .byteEnd)
        try c.encode([feature], forKey: .features)
    }
}

/// One image in an `app.bsky.embed.images` write.
public struct ImageWrite: Encodable, Equatable, Sendable {
    public let image: BlobRef
    public let alt: String

    public init(image: BlobRef, alt: String) {
        self.image = image
        self.alt = alt
    }
}

/// The images embed for a record write (`app.bsky.embed.images`).
public struct ImagesEmbedWrite: Encodable, Equatable, Sendable {
    public let images: [ImageWrite]

    public init(images: [ImageWrite]) {
        self.images = images
    }

    enum CodingKeys: String, CodingKey { case type = "$type", images }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.embed.images", forKey: .type)
        try c.encode(images, forKey: .images)
    }
}

/// A strong reference (`com.atproto.repo.strongRef`): a record's uri + cid.
public struct StrongRef: Codable, Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) {
        self.uri = uri
        self.cid = cid
    }
}

/// The reply refs for a post record write: the conversation root and the immediate parent.
public struct ReplyRefWrite: Encodable, Equatable, Sendable {
    public let root: StrongRef
    public let parent: StrongRef

    public init(root: StrongRef, parent: StrongRef) {
        self.root = root
        self.parent = parent
    }
}

/// A post record for `createRecord` (`app.bsky.feed.post`). Encodes `$type`; omits
/// `facets`/`embed`/`reply` when absent so empty fields never reach the PDS.
public struct PostRecordWrite: Encodable, Equatable, Sendable {
    public let text: String
    public let createdAt: String
    public let facets: [FacetWrite]
    public let embed: ImagesEmbedWrite?
    public let reply: ReplyRefWrite?

    public init(text: String, createdAt: String, facets: [FacetWrite],
                embed: ImagesEmbedWrite?, reply: ReplyRefWrite?) {
        self.text = text
        self.createdAt = createdAt
        self.facets = facets
        self.embed = embed
        self.reply = reply
    }

    enum CodingKeys: String, CodingKey { case type = "$type", text, createdAt, facets, embed, reply }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.post", forKey: .type)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        if !facets.isEmpty { try c.encode(facets, forKey: .facets) }
        try c.encodeIfPresent(embed, forKey: .embed)
        try c.encodeIfPresent(reply, forKey: .reply)
    }
}

/// `createRecord` request body wrapping a typed record.
public struct CreateRecordRequest<Record: Encodable>: Encodable {
    public let repo: String
    public let collection: String
    public let record: Record

    public init(repo: String, collection: String, record: Record) {
        self.repo = repo
        self.collection = collection
        self.record = record
    }
}

/// `com.atproto.repo.uploadBlob` response.
public struct UploadBlobResponse: Decodable, Equatable, Sendable {
    public let blob: BlobRef
}

/// `com.atproto.repo.createRecord` response.
public struct CreateRecordResponse: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
}

/// Minimal `app.bsky.actor.getProfile` decode used to resolve a mention handle to a DID.
public struct ResolveDIDResponse: Decodable, Equatable, Sendable {
    public let did: String
}

/// Minimal `com.atproto.repo.getRecord` decode used to build reply refs from a parent URI.
public struct GetRecordResponse: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
    public let replyRoot: StrongRef?

    enum CodingKeys: String, CodingKey { case uri, cid, value }
    enum ValueKeys: String, CodingKey { case reply }
    enum ReplyKeys: String, CodingKey { case root }

    public init(uri: String, cid: String, replyRoot: StrongRef?) {
        self.uri = uri
        self.cid = cid
        self.replyRoot = replyRoot
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try c.decode(String.self, forKey: .uri)
        self.cid = try c.decode(String.self, forKey: .cid)
        let value = try? c.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
        let reply = try? value?.nestedContainer(keyedBy: ReplyKeys.self, forKey: .reply)
        self.replyRoot = try? reply?.decode(StrongRef.self, forKey: .root)
    }
}
```

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter PostWriteTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/Models/PostWrite.swift core/Sources/BlueskyCore/Models/Timeline.swift core/Tests/BlueskyCoreTests/PostWriteTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add post write models (PostRecordWrite, FacetWrite, images embed, BlobRef, reply refs) and FacetFeature Encodable"
```

---

## Task 5: PostService — uploadBlob

**Files:**
- Create: `core/Sources/BlueskyCore/XRPC/PostService.swift`
- Test: `core/Tests/BlueskyCoreTests/PostServiceTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import BlueskyCore

final class PostServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private func makeService(http: HTTPClient) -> PostService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return PostService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testUploadBlobPostsBytesWithMimeTypeAndDecodes() async throws {
        let body = Data(##"""
        {"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/jpeg","size":3}}
        """##.utf8)
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: body))
        let service = makeService(http: http)

        let result = try await service.uploadBlob(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            data: Data([0x1, 0x2, 0x3]), mimeType: "image/jpeg"
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.blob.cid, "bafycid")
        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .post)
        XCTAssertTrue(sent.url.absoluteString.hasSuffix("/xrpc/com.atproto.repo.uploadBlob"))
        XCTAssertEqual(sent.headers["Content-Type"], "image/jpeg")
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
        XCTAssertEqual(sent.body, Data([0x1, 0x2, 0x3]))
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter PostServiceTests`
Expected: コンパイルエラー（`PostService` 未定義）

- [ ] **Step 3: 最小実装**

```swift
import Foundation

/// Writes posts to the account's PDS over a DPoP-bound channel: uploads image
/// blobs (`com.atproto.repo.uploadBlob`) and creates the post record
/// (`com.atproto.repo.createRecord` / `app.bsky.feed.post`). Mirrors the auth
/// handling of `TimelineService`/`ProfileService`: the `use_dpop_nonce` retry lives
/// in the sender, and a 401 that is not a nonce challenge refreshes via
/// `refresh_token` and retries once. Because a single createPost makes several
/// requests, the latest refreshed tokens are threaded forward and returned so the
/// caller can persist them.
public struct PostService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig

    public init(sender: DPoPRequestSender, metadataResolver: OAuthMetadataResolver, config: OAuthClientConfig) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
    }

    public func uploadBlob(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        data: Data, mimeType: String
    ) async throws -> (blob: BlobRef, refreshed: TokenResponse?) {
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
        let headers = ["Content-Type": mimeType, "Accept": "application/json"]
        let outcome = try await perform(method: .post, url: url, headers: headers, body: data,
                                        issuer: issuer, accessToken: accessToken, refreshToken: refreshToken)
        let decoded: UploadBlobResponse = try Self.decode(outcome.response)
        return (decoded.blob, outcome.refreshed)
    }

    /// One authorized request with a 401→refresh→retry-once. Returns the response
    /// and, when a refresh occurred, the freshly issued tokens.
    func perform(
        method: HTTPMethod, url: URL, headers: [String: String], body: Data?,
        issuer: URL, accessToken: String, refreshToken: String?
    ) async throws -> (response: HTTPResponse, refreshed: TokenResponse?) {
        let response = try await sender.send(method: method, url: url, accessToken: accessToken,
                                             headers: headers, body: body)
        if response.statusCode == 401, !DPoPRequestSender.isNonceChallenge(response), let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await sender.send(method: method, url: url, accessToken: tokens.accessToken,
                                                headers: headers, body: body)
            return (retried, tokens)
        }
        return (response, nil)
    }

    private func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
        return try await TokenService(sender: sender).requestToken(
            metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
        )
    }

    static func decode<T: Decodable>(_ response: HTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter PostServiceTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/XRPC/PostService.swift core/Tests/BlueskyCoreTests/PostServiceTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add PostService.uploadBlob with DPoP auth and 401 refresh retry"
```

---

## Task 6: PostService — createPost（facet 結合・mention 解決・画像 embed）

**Files:**
- Modify: `core/Sources/BlueskyCore/XRPC/PostService.swift`
- Test: `core/Tests/BlueskyCoreTests/PostServiceTests.swift`

- [ ] **Step 1: 失敗するテストを追加**

`RoutingHTTPClient`（既存 Support）で nsid ごとに応答を返す。まず既存実装を確認:
Run: `cd core && swift test --filter PostServiceTests` 実行前に `core/Tests/BlueskyCoreTests/Support/RoutingHTTPClient.swift` を読み、`route(_ predicate:, response:)` 形式の API を使う。

```swift
extension PostServiceTests {
    func testCreatePostResolvesMentionAndSendsFacets() async throws {
        let profile = HTTPResponse(statusCode: 200, body: Data(##"{"did":"did:plc:alice"}"##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = RoutingHTTPClient { request in
            if request.url.absoluteString.contains("app.bsky.actor.getProfile") { return profile }
            if request.url.absoluteString.contains("com.atproto.repo.createRecord") { return created }
            return HTTPResponse(statusCode: 500, body: Data())
        }
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "hi @alice.bsky.social #swift https://x.io",
            images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.response.uri, "at://did:plc:me/app.bsky.feed.post/abc")
        // The createRecord body must carry three facets sorted by byteStart.
        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let body = try XCTUnwrap(createReq.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        let facets = try XCTUnwrap(record["facets"] as? [[String: Any]])
        XCTAssertEqual(facets.count, 3)
        let types = facets.compactMap { ($0["features"] as? [[String: Any]])?.first?["$type"] as? String }
        XCTAssertEqual(types, [
            "app.bsky.richtext.facet#mention",
            "app.bsky.richtext.facet#tag",
            "app.bsky.richtext.facet#link",
        ])
    }

    func testCreatePostDropsMentionWhenResolutionFails() async throws {
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = RoutingHTTPClient { request in
            if request.url.absoluteString.contains("getProfile") {
                return HTTPResponse(statusCode: 400, body: Data(##"{"error":"InvalidRequest"}"##.utf8))
            }
            if request.url.absoluteString.contains("createRecord") { return created }
            return HTTPResponse(statusCode: 500, body: Data())
        }
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "yo @ghost.invalid hello", images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.response.cid, "bafypost")
        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(createReq.body)) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        XCTAssertNil(record["facets"]) // mention dropped, no other facets -> omitted
    }
}
```

注: `RoutingHTTPClient` の実際の初期化シグネチャに合わせて呼び出しを調整すること（Step 1 冒頭で確認）。クロージャ型でなければ、`route` 登録 API を使う。

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter PostServiceTests`
Expected: FAIL（`createPost` 未定義）

- [ ] **Step 3: 実装（`PostService` に追加）**

```swift
    /// Create an `app.bsky.feed.post`. Uploads any images first, detects link/tag
    /// facets, resolves `@handle` mentions to DIDs (dropping any that fail), builds
    /// the record, and sends `createRecord`. Threads refreshed tokens across all the
    /// sub-requests and returns the latest so the caller can persist them.
    public func createPost(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        did: String, text: String, images: [(data: Data, mimeType: String, alt: String)],
        replyParentURI: String?,
        createdAt: String = Self.timestamp()
    ) async throws -> (response: CreateRecordResponse, refreshed: TokenResponse?) {
        var token = accessToken
        var currentRefresh = refreshToken
        var refreshed: TokenResponse? = nil

        func authed(method: HTTPMethod, url: URL, headers: [String: String], body: Data?) async throws -> HTTPResponse {
            let outcome = try await perform(method: method, url: url, headers: headers, body: body,
                                            issuer: issuer, accessToken: token, refreshToken: currentRefresh)
            if let tokens = outcome.refreshed {
                refreshed = tokens
                token = tokens.accessToken
                currentRefresh = tokens.refreshToken ?? currentRefresh
            }
            return outcome.response
        }

        // 1. Upload images.
        var imageWrites: [ImageWrite] = []
        for image in images {
            let url = pds.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
            let response = try await authed(method: .post, url: url,
                                            headers: ["Content-Type": image.mimeType, "Accept": "application/json"],
                                            body: image.data)
            let decoded: UploadBlobResponse = try Self.decode(response)
            imageWrites.append(ImageWrite(image: decoded.blob, alt: image.alt))
        }

        // 2. Detect facets; resolve mention handles to DIDs.
        var facets: [FacetWrite] = []
        for detected in FacetDetector.detect(text: text) {
            switch detected.feature {
            case .link(let uri):
                facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .link(uri: uri)))
            case .tag(let tag):
                facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .tag(tag: tag)))
            case .mentionCandidate(let handle):
                if let didValue = try await resolveDID(handle: handle, pds: pds, authed: authed) {
                    facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .mention(did: didValue)))
                }
            }
        }
        facets.sort { $0.byteStart < $1.byteStart }

        // 3. Resolve reply refs from the parent URI.
        var reply: ReplyRefWrite? = nil
        if let replyParentURI {
            reply = try await fetchReplyRefs(parentURI: replyParentURI, pds: pds, authed: authed)
        }

        // 4. Build and send the record.
        let embed = imageWrites.isEmpty ? nil : ImagesEmbedWrite(images: imageWrites)
        let record = PostRecordWrite(text: text, createdAt: createdAt, facets: facets, embed: embed, reply: reply)
        let request = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        let payload = try JSONEncoder().encode(request)
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.createRecord")
        let response = try await authed(method: .post, url: url,
                                        headers: ["Content-Type": "application/json", "Accept": "application/json"],
                                        body: payload)
        let decoded: CreateRecordResponse = try Self.decode(response)
        return (decoded, refreshed)
    }

    /// Resolve `@handle` to a DID via getProfile. Returns nil on any failure so the
    /// caller drops the mention facet and leaves the text plain.
    private func resolveDID(
        handle: String, pds: URL,
        authed: (HTTPMethod, URL, [String: String], Data?) async throws -> HTTPResponse
    ) async throws -> String? {
        guard var components = URLComponents(
            url: pds.appendingPathComponent("xrpc/app.bsky.actor.getProfile"), resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [URLQueryItem(name: "actor", value: handle)]
        guard let url = components.url else { return nil }
        let response = try await authed(.get, url, ["Accept": "application/json"], nil)
        guard (200..<300).contains(response.statusCode) else { return nil }
        return (try? JSONDecoder().decode(ResolveDIDResponse.self, from: response.body))?.did
    }

    /// Build reply refs from a parent at:// URI: getRecord the parent, reuse its
    /// conversation root when it is itself a reply, otherwise the parent is the root.
    private func fetchReplyRefs(
        parentURI: String, pds: URL,
        authed: (HTTPMethod, URL, [String: String], Data?) async throws -> HTTPResponse
    ) async throws -> ReplyRefWrite {
        let parts = parentURI.replacingOccurrences(of: "at://", with: "").split(separator: "/", maxSplits: 2)
        guard parts.count == 3 else { throw XRPCError.invalidURL(parentURI) }
        guard var components = URLComponents(
            url: pds.appendingPathComponent("xrpc/com.atproto.repo.getRecord"), resolvingAgainstBaseURL: false
        ) else { throw XRPCError.invalidURL(parentURI) }
        components.queryItems = [
            URLQueryItem(name: "repo", value: String(parts[0])),
            URLQueryItem(name: "collection", value: String(parts[1])),
            URLQueryItem(name: "rkey", value: String(parts[2])),
        ]
        guard let url = components.url else { throw XRPCError.invalidURL(parentURI) }
        let response = try await authed(.get, url, ["Accept": "application/json"], nil)
        let decoded: GetRecordResponse = try Self.decode(response)
        let parentRef = StrongRef(uri: decoded.uri, cid: decoded.cid)
        return ReplyRefWrite(root: decoded.replyRoot ?? parentRef, parent: parentRef)
    }

    /// ISO8601 timestamp with milliseconds and a `Z` suffix, matching atproto records.
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
```

注: `authed` クロージャは `var` をキャプチャするため、`resolveDID`/`fetchReplyRefs` には関数値として渡す。Swift 6 の `Sendable` 検査で警告が出る場合は、これらヘルパを `createPost` 内のローカル関数に展開してもよい（同等の振る舞い）。

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter PostServiceTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Sources/BlueskyCore/XRPC/PostService.swift core/Tests/BlueskyCoreTests/PostServiceTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add PostService.createPost: facet join, mention DID resolution, image embed, reply refs"
```

---

## Task 7: PostService — リプライ ref とトークンリフレッシュの結合テスト

**Files:**
- Test: `core/Tests/BlueskyCoreTests/PostServiceTests.swift`

- [ ] **Step 1: 失敗するテストを追加**

```swift
extension PostServiceTests {
    func testCreateReplyBuildsRootAndParentFromParentRecord() async throws {
        // Parent is itself a reply, so its reply.root must be reused as the root.
        let getRecord = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:bob/app.bsky.feed.post/parent","cid":"bafyparent",
         "value":{"reply":{"root":{"uri":"at://did:plc:bob/app.bsky.feed.post/root","cid":"bafyroot"}}}}
        """##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/new","cid":"bafynew"}
        """##.utf8))
        let http = RoutingHTTPClient { request in
            if request.url.absoluteString.contains("getRecord") { return getRecord }
            if request.url.absoluteString.contains("createRecord") { return created }
            return HTTPResponse(statusCode: 500, body: Data())
        }
        let service = makeService(http: http)

        _ = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            did: "did:plc:me", text: "thanks", images: [],
            replyParentURI: "at://did:plc:bob/app.bsky.feed.post/parent"
        )

        let createReq = try XCTUnwrap(http.sentRequests.first { $0.url.absoluteString.contains("createRecord") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(createReq.body)) as? [String: Any])
        let record = try XCTUnwrap(json["record"] as? [String: Any])
        let reply = try XCTUnwrap(record["reply"] as? [String: Any])
        let root = try XCTUnwrap(reply["root"] as? [String: Any])
        let parent = try XCTUnwrap(reply["parent"] as? [String: Any])
        XCTAssertEqual(root["uri"] as? String, "at://did:plc:bob/app.bsky.feed.post/root")
        XCTAssertEqual(parent["uri"] as? String, "at://did:plc:bob/app.bsky.feed.post/parent")
    }

    func testCreatePostRefreshesOnUnauthorizedCreateRecord() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token"}
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:me"}
        """##.utf8))
        let created = HTTPResponse(statusCode: 200, body: Data(##"""
        {"uri":"at://did:plc:me/app.bsky.feed.post/abc","cid":"bafypost"}
        """##.utf8))
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, created])
        let service = makeService(http: http)

        let result = try await service.createPost(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk",
            did: "did:plc:me", text: "plain text", images: [], replyParentURI: nil
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.cid, "bafypost")
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter PostServiceTests`
Expected: 既存実装で通る想定（Task 6 実装でカバー済み）。もし FAIL なら実装を修正。

- [ ] **Step 3: 必要なら修正**

`fetchReplyRefs` の URI 分割や `perform` のトークン threading を実テストに合わせて調整する。

- [ ] **Step 4: 全テスト実行**

Run: `cd core && swift test`
Expected: PASS（全テストグリーン）

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add core/Tests/BlueskyCoreTests/PostServiceTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add reply-ref and token-refresh tests for PostService.createPost"
```

---

## Task 8: ComposerViewModel（YoruMimizukuKit）

**Files:**
- Create: `core/Sources/YoruMimizukuKit/PostDraft.swift`
- Create: `core/Sources/YoruMimizukuKit/PostSubmitting.swift`
- Create: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift`
- Test: `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ComposerViewModelTests: XCTestCase {
    private final class FakeSubmitter: PostSubmitting, @unchecked Sendable {
        var received: PostDraft?
        var result: Result<PostResult, Error> = .success(PostResult(uri: "at://x", cid: "c"))
        func submit(_ draft: PostDraft) async throws -> PostResult {
            received = draft
            return try result.get()
        }
    }

    func testCanSubmitRequiresContentWithinLimit() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        XCTAssertFalse(vm.canSubmit) // empty
        vm.text = "hello"
        XCTAssertTrue(vm.canSubmit)
        vm.text = String(repeating: "a", count: 301)
        XCTAssertFalse(vm.canSubmit) // over 300 graphemes
        XCTAssertEqual(vm.remaining, -1)
    }

    func testGraphemeCountCountsClustersNotUTF16() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        vm.text = "👨‍👩‍👧‍👦" // one grapheme cluster
        XCTAssertEqual(vm.graphemeCount, 1)
        XCTAssertTrue(vm.canSubmit)
    }

    func testSubmitForwardsDraftAndReportsSuccess() async {
        let submitter = FakeSubmitter()
        let vm = ComposerViewModel(submitter: submitter, replyParentURI: "at://parent")
        vm.text = "hi"
        var posted = false
        vm.onPosted = { posted = true }

        await vm.submit()

        XCTAssertEqual(submitter.received?.text, "hi")
        XCTAssertEqual(submitter.received?.replyParentURI, "at://parent")
        XCTAssertTrue(posted)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }

    func testSubmitSetsErrorMessageOnFailure() async {
        let submitter = FakeSubmitter()
        submitter.result = .failure(NSError(domain: "x", code: 1))
        let vm = ComposerViewModel(submitter: submitter)
        vm.text = "hi"

        await vm.submit()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `cd core && swift test --filter ComposerViewModelTests`
Expected: コンパイルエラー（型未定義）

- [ ] **Step 3: 実装**

`core/Sources/YoruMimizukuKit/PostDraft.swift`:

```swift
import Foundation

/// One image attached to a draft: raw bytes plus its MIME type and alt text.
public struct ComposeImage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var data: Data
    public var mimeType: String
    public var alt: String

    public init(id: UUID = UUID(), data: Data, mimeType: String, alt: String = "") {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.alt = alt
    }
}

/// The values needed to create a post: body text, up to four images, and an
/// optional parent URI when the post is a reply.
public struct PostDraft: Equatable, Sendable {
    public var text: String
    public var images: [ComposeImage]
    public var replyParentURI: String?

    public init(text: String, images: [ComposeImage] = [], replyParentURI: String? = nil) {
        self.text = text
        self.images = images
        self.replyParentURI = replyParentURI
    }
}

/// The created post's identifiers, returned on success.
public struct PostResult: Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) {
        self.uri = uri
        self.cid = cid
    }
}
```

`core/Sources/YoruMimizukuKit/PostSubmitting.swift`:

```swift
/// Submits a composed post. The app wires a live implementation backed by
/// `PostService`; tests inject a fake. Abstracting the side effect keeps
/// `ComposerViewModel` free of networking and Apple-framework dependencies.
public protocol PostSubmitting: Sendable {
    func submit(_ draft: PostDraft) async throws -> PostResult
}
```

`core/Sources/YoruMimizukuKit/ComposerViewModel.swift`:

```swift
import Foundation

/// Drives the composer sheet: holds the draft body and images, exposes the
/// grapheme-based character budget (Bluesky caps posts at 300 graphemes), and
/// submits through an injected `PostSubmitting`. Lives in the kit so its logic is
/// unit-tested without SwiftUI.
@MainActor
public final class ComposerViewModel: ObservableObject {
    public static let maxGraphemes = 300
    public static let maxImages = 4

    @Published public var text: String = ""
    @Published public var images: [ComposeImage] = []
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var errorMessage: String?

    public let replyParentURI: String?
    /// Called after a successful submit so the view can dismiss and refresh.
    public var onPosted: (() -> Void)?

    private let submitter: PostSubmitting

    public init(submitter: PostSubmitting, replyParentURI: String? = nil) {
        self.submitter = submitter
        self.replyParentURI = replyParentURI
    }

    /// Grapheme-cluster count (not UTF-16 length) so emoji and combined marks count as one.
    public var graphemeCount: Int { text.count }
    public var remaining: Int { Self.maxGraphemes - graphemeCount }
    public var canAddImage: Bool { images.count < Self.maxImages }

    public var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard graphemeCount <= Self.maxGraphemes else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !images.isEmpty
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let draft = PostDraft(text: text, images: images, replyParentURI: replyParentURI)
        do {
            _ = try await submitter.submit(draft)
            isSubmitting = false
            onPosted?()
        } catch {
            isSubmitting = false
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: 通ることを確認**

Run: `cd core && swift test --filter ComposerViewModelTests`
Expected: PASS

- [ ] **Step 5: 全テスト実行してコミット**

```bash
cd core && swift test
cd ..
git -C .worktrees/feature/compose-post add core/Sources/YoruMimizukuKit/PostDraft.swift core/Sources/YoruMimizukuKit/PostSubmitting.swift core/Sources/YoruMimizukuKit/ComposerViewModel.swift core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add ComposerViewModel, PostDraft, and PostSubmitting protocol with grapheme limit"
```

---

## Task 9: apps/macos — LiveComposer 結線とコンポーザシート UI

ここは Apple フレームワーク依存のため手動ビルドで検証する（既存ビュー方針に準拠）。

**Files:**
- Create: `apps/macos/Compose/LiveComposer.swift`
- Create: `apps/macos/Views/ComposerView.swift`
- Modify: `apps/macos/Views/MainWindowView.swift`

- [ ] **Step 1: LiveComposer を作成**

`apps/macos/Compose/LiveComposer.swift`:

```swift
import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `PostSubmitting`: builds a `LiveServiceContext`, runs `PostService.createPost`
/// with the draft's text/images/reply parent, and persists any refreshed tokens.
struct LiveComposer: PostSubmitting {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func submit(_ draft: PostDraft) async throws -> PostResult {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = PostService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )
        let images = draft.images.map { (data: $0.data, mimeType: $0.mimeType, alt: $0.alt) }
        let result = try await service.createPost(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            did: context.account.did,
            text: draft.text,
            images: images,
            replyParentURI: draft.replyParentURI
        )
        try context.persist(result.refreshed)
        return PostResult(uri: result.response.uri, cid: result.response.cid)
    }
}
```

- [ ] **Step 2: ComposerView シートを作成**

`apps/macos/Views/ComposerView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import YoruMimizukuKit

/// The composer sheet: a multiline editor with a grapheme budget, up to four image
/// thumbnails with alt-text fields, and a Post button gated on `canSubmit`.
struct ComposerView: View {
    @ObservedObject var model: ComposerViewModel
    @EnvironmentObject private var theme: ThemeStore
    var onClose: () -> Void

    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.replyParentURI == nil ? "新規投稿" : "返信")
                    .font(.headline)
                Spacer()
                Button("キャンセル") { onClose() }
            }
            TextEditor(text: $model.text)
                .frame(minHeight: 120)
                .font(.body)
            if !model.images.isEmpty {
                imageStrip
            }
            HStack {
                Button { importing = true } label: { Image(systemName: "photo.badge.plus") }
                    .disabled(!model.canAddImage)
                Spacer()
                Text("\(model.remaining)")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(model.remaining < 0 ? Color.red : theme.tertiaryText)
                Button("Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
            }
            if model.isSubmitting { ProgressView().controlSize(.small) }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onChange(of: model.isSubmitting) { _, _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
    }

    private var imageStrip: some View {
        VStack(spacing: 8) {
            ForEach($model.images) { $image in
                HStack(alignment: .top, spacing: 8) {
                    if let nsImage = NSImage(data: image.data) {
                        Image(nsImage: nsImage).resizable().scaledToFill()
                            .frame(width: 56, height: 56).clipped().cornerRadius(6)
                    }
                    TextField("alt text", text: $image.alt)
                    Button { model.images.removeAll { $0.id == image.id } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls where model.canAddImage {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            model.images.append(ComposeImage(data: data, mimeType: mime))
        }
    }
}
```

- [ ] **Step 3: MainWindowView に `n` キーとシート提示を結線**

`apps/macos/Views/MainWindowView.swift` の変更:

1. プロパティを追加（`@State private var focusedPostID` の近く）:

```swift
    /// The composer sheet's view model; non-nil while the sheet is open.
    @State private var composer: ComposerViewModel?
```

2. コンポーザ生成のため `AccountManager`/`config` を受け取る必要がある。`MainWindowView` の呼び出し元（`RootView`）から `makeComposer: @MainActor (String?) -> ComposerViewModel` を注入する。`MainWindowView` にプロパティ追加:

```swift
    /// Builds a composer VM for a new post (nil parent) or a reply (parent URI).
    var makeComposer: @MainActor (String?) -> ComposerViewModel
```

3. `body` の `.sheet(isPresented: $showSettings)` の後に追加:

```swift
        .sheet(item: $composer) { model in
            ComposerView(model: model) { composer = nil }
                .environmentObject(theme)
        }
```

   `ComposerViewModel` を `Identifiable` にするため、Task 8 の VM に `public let id = UUID()` を追加し `: ObservableObject, Identifiable` にする。

4. `n` キーの background ボタンを `postNavShortcuts` に追加（新規投稿）:

```swift
            Button("") {
                let vm = makeComposer(nil)
                vm.onPosted = { composer = nil; Task { await model.refresh() } }
                composer = vm
            }
            .keyboardShortcut("n", modifiers: [])
```

5. `RootView`（呼び出し元）で `makeComposer` を渡す:

```swift
            makeComposer: { parentURI in
                ComposerViewModel(submitter: LiveComposer(accountManager: accountManager), replyParentURI: parentURI)
            }
```

   （`RootView` が `accountManager` を保持していることを確認。なければ `LiveTimelineLoader` 同様の注入経路に合わせる。）

- [ ] **Step 4: プロジェクト生成とビルド**

Run:
```bash
cd .worktrees/feature/compose-post && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: 手動確認とコミット**

アプリを起動し、`n` で新規投稿シートが開くこと、URL/ハッシュタグ/メンションを含む本文と画像（最大4枚）を投稿でき、ホームに反映されることを確認。

```bash
git -C .worktrees/feature/compose-post add apps/macos/Compose/LiveComposer.swift apps/macos/Views/ComposerView.swift apps/macos/Views/MainWindowView.swift core/Sources/YoruMimizukuKit/ComposerViewModel.swift
git -C .worktrees/feature/compose-post ai-commit --context "Wire compose sheet: LiveComposer, ComposerView, n-key new post in MainWindowView"
```

---

## Task 10: 返信導線（PostRowView の返信ボタン → リプライコンポーザ）

**Files:**
- Modify: `apps/macos/Views/MainWindowView.swift`
- Modify: `apps/macos/Views/ConversationView.swift`（返信ボタンのコールバック確認）

- [ ] **Step 1: 既存の返信導線を確認**

`PostRowView` の `onReplyTap` は現在 `workspace.openConversation` に繋がっている（会話タブを開く）。返信投稿はこれとは別アクション。`PostRowView` に返信投稿用の別ボタン、または会話タブ内に「返信」ボタンを追加する。まず `ConversationView.swift` と `PostRowView.swift` を読み、最小の導線を決める。

- [ ] **Step 2: リプライコンポーザを開く導線を実装**

会話タブ（`ConversationView`）のヘッダまたは各行に「返信」ボタンを追加し、押下で `makeComposer(post.uri)` を生成してシート提示する。`MainWindowView` の `detail` で `ConversationView` に `onReply: (String) -> Void` を渡し、`composer` をセットする:

```swift
                ConversationView(
                    model: tab.model,
                    title: tab.title,
                    now: now,
                    onImageTap: { lightboxURL = $0 },
                    onOpenConversation: { workspace.openConversation($0) },
                    onClose: { workspace.closeConversation(id) },
                    onReply: { parentURI in
                        let vm = makeComposer(parentURI)
                        vm.onPosted = { composer = nil }
                        composer = vm
                    }
                )
```

`ConversationView` に `var onReply: (String) -> Void` を追加し、返信ボタンから `onReply(post.id)` を呼ぶ（`post.id` は投稿 URI）。

- [ ] **Step 3: ビルド**

Run:
```bash
cd .worktrees/feature/compose-post && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: 手動確認**

会話タブから「返信」を押すとリプライ先 URI 付きでコンポーザが開き、投稿後に親スレッドへ反映されることを確認。

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/compose-post add apps/macos/Views/ConversationView.swift apps/macos/Views/MainWindowView.swift
git -C .worktrees/feature/compose-post ai-commit --context "Add reply entry point from conversation view to the composer sheet"
```

---

## Self-Review（計画 vs 仕様）

- **link facet**: Task 1（末尾句読点トリム含む）✓
- **tag facet**: Task 2（全角・64上限・数字のみ除外・バイトオフセット）✓
- **mention facet**: Task 3（候補検出）＋ Task 6（getProfile で DID 解決、失敗時ドロップ）✓
- **画像投稿（最大4枚・alt）**: Task 5（uploadBlob）＋ Task 6（embed 組み立て）＋ Task 8（`maxImages`）＋ Task 9（UI、alt 入力）✓
- **URL は facet のみ（カードなし）**: external embed を作らない設計に一致 ✓
- **新規投稿**: Task 6 + Task 9 ✓
- **リプライ**: Task 6（reply refs）＋ Task 7（root 引き継ぎテスト）＋ Task 10（UI 導線）✓
- **300 グラフェム制限**: Task 8 ✓
- **`n` キーでシート**: Task 9 ✓
- **401→refresh リトライ／トークン永続化**: Task 5/6/7 ✓
- **型整合性**: `FacetDetector.Feature`（link/tag/mentionCandidate）→ `PostService` で `FacetFeature`（link/tag/mention）に変換。`BlobRef`/`CreateRecordResponse`/`PostResult` の命名は全タスクで一貫 ✓

未確定（実装時に確認）:
- `RoutingHTTPClient` の正確な初期化 API（Task 6 Step 1 で確認）
- `RootView` の `accountManager` 注入経路（Task 9 Step 3）
- `ConversationView`/`PostRowView` の既存返信ボタンの有無（Task 10 Step 1）
