# Account Persistence Implementation Plan (Plan 9a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ログイン結果（DID / PDS / issuer / トークン / DPoP 秘密鍵）を Keychain に per-DID で永続化し、複数アカウントの index と現在アカウントを管理する `AccountStore` / `AccountManager` を BlueskyCore に追加する。

**Architecture:** `SecureStorage` プロトコルで安全領域を抽象化し、Apple 実体 `KeychainStorage`（`SecItem` 汎用パスワード）を提供する。`AccountStore` は `SecureStorage` 上に per-DID の `PersistedAccount`（JSON）と `AccountsIndex`（DID 一覧 + 現在 DID）を読み書きする純粋ロジック。`AccountManager` はその上でアカウントの追加・切替・削除・現在取得を提供する。CryptoKit 依存（DPoP 鍵の生成/復元）は本層に持ち込まず、`PersistedAccount` は鍵を生バイト列 `Data` として保持する（Apple 配線層が `P256` へ復元する）。これにより BlueskyCore はクロスプラットフォームのまま保てる。

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation (`JSONEncoder`/`JSONDecoder`), Security (`SecItem*`, Apple 実体のみ)。

**Scope note:** トークンの自動リフレッシュとスケジューリング、`ASWebAuthenticationSession` 実体、`OAuthClient` 実配線、ログイン UI、アプリ統合は Plan 9b に属する。本プランは「ログイン結果を安全に保存し、現在/複数アカウントを管理する」までの純粋ロジック + Keychain 実体に限定する。`KeychainStorage`（OS 実体）は headless な `swift test` で署名要件により失敗しうるため単体テストせず、ビルド成功で検証する。ロジックのテストはすべてインメモリの `SecureStorage` フェイクで行う。

---

## File Structure

- Create: `BlueskyCore/Sources/BlueskyCore/Platform/SecureStorage.swift` — 安全領域の抽象プロトコル。
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/KeychainStorage.swift` — Apple 実体（`SecItem`）。
- Create: `BlueskyCore/Sources/BlueskyCore/Account/PersistedAccount.swift` — 永続化アカウントモデル + index モデル。
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountStore.swift` — `SecureStorage` 上の読み書き。
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountManager.swift` — 高レベルのアカウント管理。
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountError.swift` — アカウント層のエラー。
- Test: `BlueskyCore/Tests/BlueskyCoreTests/PersistedAccountTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AccountStoreTests.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AccountManagerTests.swift`
- Test support: `BlueskyCore/Tests/BlueskyCoreTests/Support/InMemorySecureStorage.swift`

**Existing context to reuse (do NOT recreate):**
- `OAuthLoginResult` (`OAuth/OAuthClient.swift`): `did`, `pds: URL`, `authorizationServerIssuer: String`, `tokens: TokenResponse`。
- `TokenResponse` (`OAuth/TokenResponse.swift`): `accessToken`, `tokenType`, `refreshToken: String?`, `expiresIn: Int?`, `scope: String?`, `sub`。
- 既存テスト Support の `@unchecked Sendable` フェイクの書き方（`FakeHTTPClient.swift`）を参照。

---

### Task 1: SecureStorage protocol + KeychainStorage (Apple) + in-memory fake

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/SecureStorage.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/Platform/KeychainStorage.swift`
- Create: `BlueskyCore/Tests/BlueskyCoreTests/Support/InMemorySecureStorage.swift`

- [ ] **Step 1: Write the in-memory fake (test support) first — it is the test seam for later tasks**

```swift
import Foundation
@testable import BlueskyCore

/// In-memory `SecureStorage` for tests. `@unchecked Sendable`: used serially
/// within async tests, matching the existing `FakeHTTPClient` convention.
final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    private var items: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws { items[key] = data }
    func data(for key: String) throws -> Data? { items[key] }
    func remove(for key: String) throws { items[key] = nil }
}
```

- [ ] **Step 2: Write a failing test that drives the protocol shape**

Add to a new file `BlueskyCore/Tests/BlueskyCoreTests/AccountStoreTests.swift` a minimal first test that only exercises the fake against the protocol (this also proves the protocol compiles):

```swift
import XCTest
@testable import BlueskyCore

final class AccountStoreTests: XCTestCase {
    func testInMemoryStorageRoundTrips() throws {
        let storage: SecureStorage = InMemorySecureStorage()
        XCTAssertNil(try storage.data(for: "k"))
        try storage.set(Data([1, 2, 3]), for: "k")
        XCTAssertEqual(try storage.data(for: "k"), Data([1, 2, 3]))
        try storage.remove(for: "k")
        XCTAssertNil(try storage.data(for: "k"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AccountStoreTests`
Expected: FAIL — `cannot find type 'SecureStorage' in scope`.

- [ ] **Step 4: Write the protocol**

`SecureStorage.swift`:

```swift
import Foundation

/// Abstraction over a secure key/value store (Apple: Keychain). Keys are opaque
/// strings; values are raw `Data`. One of the OS-touchpoint abstractions in the
/// design. Tests inject an in-memory fake.
public protocol SecureStorage: Sendable {
    /// Store `data` under `key`, overwriting any existing value.
    func set(_ data: Data, for key: String) throws
    /// Return the stored value for `key`, or nil if absent.
    func data(for key: String) throws -> Data?
    /// Remove the value for `key` (no-op if absent).
    func remove(for key: String) throws
}
```

- [ ] **Step 5: Write the Apple Keychain implementation**

`KeychainStorage.swift`:

```swift
import Foundation
import Security

/// Apple `SecureStorage` backed by the Keychain (generic password items keyed by
/// `service` + account key). Used for OAuth tokens and the DPoP private key.
public struct KeychainStorage: SecureStorage {
    private let service: String

    /// `service` namespaces all items (use the app bundle id, e.g. "as.ason.Hoshidukiyo").
    public init(service: String) {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    public func set(_ data: Data, for key: String) throws {
        var query = baseQuery(key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError.unexpectedStatus(update) }
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            let add = SecItemAdd(query as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError.unexpectedStatus(add) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func remove(for key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Errors from the Keychain-backed `SecureStorage`.
public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}
```

- [ ] **Step 6: Run test + build to verify**

Run: `swift test --package-path BlueskyCore --filter AccountStoreTests`
Expected: PASS (the round-trip test).
Run: `swift build --package-path BlueskyCore`
Expected: Build succeeds (KeychainStorage compiles; it is not unit-tested here).

- [ ] **Step 7: Commit**

Use the `/commit` skill (`git ai-commit`). Stage `SecureStorage.swift` + `KeychainStorage.swift` + `Support/InMemorySecureStorage.swift` + `AccountStoreTests.swift`. Behavioral change. Suggested message: `Add secure storage abstraction with Keychain implementation`.

---

### Task 2: PersistedAccount + AccountsIndex models

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Account/PersistedAccount.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/PersistedAccountTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class PersistedAccountTests: XCTestCase {
    private func sample() -> PersistedAccount {
        PersistedAccount(
            did: "did:plc:abc",
            handle: "alice.bsky.social",
            pds: URL(string: "https://pds.example")!,
            issuer: "https://bsky.social",
            accessToken: "atk",
            refreshToken: "rtk",
            scope: "atproto transition:generic",
            dpopPrivateKeyRaw: Data([0x01, 0x02, 0x03])
        )
    }

    func testRoundTripsThroughJSON() throws {
        let account = sample()
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(PersistedAccount.self, from: data)
        XCTAssertEqual(decoded, account)
    }

    func testFromLoginResultCopiesFieldsAndKey() throws {
        let tokensJSON = ##"{"access_token":"atk","token_type":"DPoP","refresh_token":"rtk","scope":"atproto","sub":"did:plc:xyz"}"##
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: Data(tokensJSON.utf8))
        let login = OAuthLoginResult(
            did: "did:plc:xyz",
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            tokens: tokens
        )
        let account = PersistedAccount(
            loginResult: login,
            handle: "bob.bsky.social",
            dpopPrivateKeyRaw: Data([0xAA])
        )
        XCTAssertEqual(account.did, "did:plc:xyz")
        XCTAssertEqual(account.handle, "bob.bsky.social")
        XCTAssertEqual(account.pds, URL(string: "https://pds.example")!)
        XCTAssertEqual(account.issuer, "https://bsky.social")
        XCTAssertEqual(account.accessToken, "atk")
        XCTAssertEqual(account.refreshToken, "rtk")
        XCTAssertEqual(account.scope, "atproto")
        XCTAssertEqual(account.dpopPrivateKeyRaw, Data([0xAA]))
    }

    func testAccountsIndexRoundTripsThroughJSON() throws {
        let index = AccountsIndex(dids: ["did:plc:a", "did:plc:b"], currentDID: "did:plc:b")
        let data = try JSONEncoder().encode(index)
        XCTAssertEqual(try JSONDecoder().decode(AccountsIndex.self, from: data), index)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter PersistedAccountTests`
Expected: FAIL — `cannot find type 'PersistedAccount' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A logged-in account persisted to secure storage. Holds the OAuth tokens and
/// the DPoP private key as raw bytes (the Apple wiring layer restores it into a
/// P-256 key); this keeps the account layer free of CryptoKit.
public struct PersistedAccount: Codable, Equatable, Sendable {
    public var did: String
    public var handle: String?
    public var pds: URL
    public var issuer: String
    public var accessToken: String
    public var refreshToken: String?
    public var scope: String?
    public var dpopPrivateKeyRaw: Data

    public init(
        did: String,
        handle: String?,
        pds: URL,
        issuer: String,
        accessToken: String,
        refreshToken: String?,
        scope: String?,
        dpopPrivateKeyRaw: Data
    ) {
        self.did = did
        self.handle = handle
        self.pds = pds
        self.issuer = issuer
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.dpopPrivateKeyRaw = dpopPrivateKeyRaw
    }

    /// Build from a successful login plus the DPoP key used during that login.
    public init(loginResult: OAuthLoginResult, handle: String?, dpopPrivateKeyRaw: Data) {
        self.init(
            did: loginResult.did,
            handle: handle,
            pds: loginResult.pds,
            issuer: loginResult.authorizationServerIssuer,
            accessToken: loginResult.tokens.accessToken,
            refreshToken: loginResult.tokens.refreshToken,
            scope: loginResult.tokens.scope,
            dpopPrivateKeyRaw: dpopPrivateKeyRaw
        )
    }
}

/// The index of known accounts and which one is current.
public struct AccountsIndex: Codable, Equatable, Sendable {
    public var dids: [String]
    public var currentDID: String?

    public init(dids: [String] = [], currentDID: String? = nil) {
        self.dids = dids
        self.currentDID = currentDID
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter PersistedAccountTests`
Expected: PASS (3 cases).

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `PersistedAccount.swift` + `PersistedAccountTests.swift`. Behavioral change. Suggested message: `Add persisted account and accounts index models`.

---

### Task 3: AccountStore

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountError.swift`
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountStore.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AccountStoreTests.swift` (add cases to the file from Task 1)

- [ ] **Step 1: Write the failing tests (append to AccountStoreTests)**

```swift
    private func sampleAccount(did: String) -> PersistedAccount {
        PersistedAccount(
            did: did,
            handle: nil,
            pds: URL(string: "https://pds.example")!,
            issuer: "https://bsky.social",
            accessToken: "atk-\(did)",
            refreshToken: "rtk",
            scope: nil,
            dpopPrivateKeyRaw: Data([0x01])
        )
    }

    func testSaveAndLoadAccount() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        XCTAssertNil(try store.account(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:a"))
        XCTAssertEqual(try store.account(did: "did:plc:a")?.accessToken, "atk-did:plc:a")
    }

    func testSaveAddsToIndexWithoutDuplicates() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:a")) // same did again
        try store.save(sampleAccount(did: "did:plc:b"))
        XCTAssertEqual(try store.index().dids, ["did:plc:a", "did:plc:b"])
    }

    func testSetAndGetCurrentDID() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        XCTAssertNil(try store.index().currentDID)
        try store.setCurrent(did: "did:plc:a")
        XCTAssertEqual(try store.index().currentDID, "did:plc:a")
    }

    func testSetCurrentToUnknownDIDThrows() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        XCTAssertThrowsError(try store.setCurrent(did: "did:plc:missing")) { error in
            XCTAssertEqual(error as? AccountError, .unknownAccount("did:plc:missing"))
        }
    }

    func testRemoveDeletesAccountAndIndexEntryAndClearsCurrent() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:b"))
        try store.setCurrent(did: "did:plc:a")
        try store.remove(did: "did:plc:a")
        XCTAssertNil(try store.account(did: "did:plc:a"))
        XCTAssertEqual(try store.index().dids, ["did:plc:b"])
        XCTAssertNil(try store.index().currentDID) // current cleared when removed
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AccountStoreTests`
Expected: FAIL — `cannot find 'AccountStore' in scope`.

- [ ] **Step 3: Write the error type and the store**

`AccountError.swift`:

```swift
import Foundation

/// Errors from the account persistence layer.
public enum AccountError: Error, Equatable {
    case unknownAccount(String)
    case noCurrentAccount
}
```

`AccountStore.swift`:

```swift
import Foundation

/// Persists accounts and the accounts index to a `SecureStorage`. Keys:
/// "account.<did>" for each account, "accounts.index" for the index. Pure logic;
/// all crypto/OS concerns live behind `SecureStorage`.
public struct AccountStore: Sendable {
    private let storage: SecureStorage
    private let indexKey = "accounts.index"

    public init(storage: SecureStorage) {
        self.storage = storage
    }

    private func accountKey(_ did: String) -> String { "account.\(did)" }

    public func index() throws -> AccountsIndex {
        guard let data = try storage.data(for: indexKey) else { return AccountsIndex() }
        return try JSONDecoder().decode(AccountsIndex.self, from: data)
    }

    private func writeIndex(_ index: AccountsIndex) throws {
        try storage.set(try JSONEncoder().encode(index), for: indexKey)
    }

    public func account(did: String) throws -> PersistedAccount? {
        guard let data = try storage.data(for: accountKey(did)) else { return nil }
        return try JSONDecoder().decode(PersistedAccount.self, from: data)
    }

    /// Save the account and add its DID to the index (no duplicates).
    public func save(_ account: PersistedAccount) throws {
        try storage.set(try JSONEncoder().encode(account), for: accountKey(account.did))
        var idx = try index()
        if !idx.dids.contains(account.did) {
            idx.dids.append(account.did)
            try writeIndex(idx)
        }
    }

    /// Set the current account. Throws `unknownAccount` if the DID is not indexed.
    public func setCurrent(did: String) throws {
        var idx = try index()
        guard idx.dids.contains(did) else { throw AccountError.unknownAccount(did) }
        idx.currentDID = did
        try writeIndex(idx)
    }

    /// Remove an account, its index entry, and clear `currentDID` if it pointed here.
    public func remove(did: String) throws {
        try storage.remove(for: accountKey(did))
        var idx = try index()
        idx.dids.removeAll { $0 == did }
        if idx.currentDID == did { idx.currentDID = nil }
        try writeIndex(idx)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AccountStoreTests`
Expected: PASS (all cases: the round-trip from Task 1 + the 5 added here).

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage `AccountError.swift` + `AccountStore.swift` + `AccountStoreTests.swift`. Behavioral change. Suggested message: `Add account store over secure storage`.

---

### Task 4: AccountManager

**Files:**
- Create: `BlueskyCore/Sources/BlueskyCore/Account/AccountManager.swift`
- Test: `BlueskyCore/Tests/BlueskyCoreTests/AccountManagerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BlueskyCore

final class AccountManagerTests: XCTestCase {
    private func loginResult(did: String) -> OAuthLoginResult {
        let json = ##"{"access_token":"atk-\##(did)","token_type":"DPoP","refresh_token":"rtk","sub":"\##(did)"}"##
        // swiftlint:disable:next force_try
        let tokens = try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        return OAuthLoginResult(
            did: did,
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            tokens: tokens
        )
    }

    private func makeManager() -> AccountManager {
        AccountManager(store: AccountStore(storage: InMemorySecureStorage()))
    }

    func testAddLoginPersistsAndBecomesCurrent() throws {
        let manager = makeManager()
        let account = try manager.add(
            loginResult: loginResult(did: "did:plc:a"),
            handle: "alice.bsky.social",
            dpopPrivateKeyRaw: Data([0x01])
        )
        XCTAssertEqual(account.did, "did:plc:a")
        XCTAssertEqual(try manager.current()?.did, "did:plc:a")
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a"])
    }

    func testSecondAddBecomesCurrentAndBothListed() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))
        XCTAssertEqual(try manager.current()?.did, "did:plc:b")
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a", "did:plc:b"])
    }

    func testSwitchChangesCurrent() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))
        try manager.switchTo(did: "did:plc:a")
        XCTAssertEqual(try manager.current()?.did, "did:plc:a")
    }

    func testRemoveCurrentClearsCurrent() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        try manager.remove(did: "did:plc:a")
        XCTAssertNil(try manager.current())
        XCTAssertEqual(try manager.allDIDs(), [])
    }

    func testCurrentIsNilWhenNoAccounts() throws {
        XCTAssertNil(try makeManager().current())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter AccountManagerTests`
Expected: FAIL — `cannot find 'AccountManager' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// High-level account management over an `AccountStore`: add a freshly logged-in
/// account (becomes current), list, switch, remove, and read the current account.
/// Token refresh and its scheduling are out of scope for this layer.
public struct AccountManager: Sendable {
    private let store: AccountStore

    public init(store: AccountStore) {
        self.store = store
    }

    /// Persist a login result (with its DPoP key) and make it the current account.
    @discardableResult
    public func add(
        loginResult: OAuthLoginResult,
        handle: String?,
        dpopPrivateKeyRaw: Data
    ) throws -> PersistedAccount {
        let account = PersistedAccount(
            loginResult: loginResult, handle: handle, dpopPrivateKeyRaw: dpopPrivateKeyRaw
        )
        try store.save(account)
        try store.setCurrent(did: account.did)
        return account
    }

    /// The current account, or nil if none is selected.
    public func current() throws -> PersistedAccount? {
        guard let did = try store.index().currentDID else { return nil }
        return try store.account(did: did)
    }

    /// All known account DIDs, in insertion order.
    public func allDIDs() throws -> [String] {
        try store.index().dids
    }

    /// Switch the current account. Throws `unknownAccount` if the DID is unknown.
    public func switchTo(did: String) throws {
        try store.setCurrent(did: did)
    }

    /// Remove an account; clears current if it pointed at the removed account.
    public func remove(did: String) throws {
        try store.remove(did: did)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter AccountManagerTests`
Expected: PASS (5 cases).

- [ ] **Step 5: Run the full suite**

Run: `swift test --package-path BlueskyCore`
Expected: all tests pass (79 prior + the new ones).

- [ ] **Step 6: Commit**

Use the `/commit` skill. Stage `AccountManager.swift` + `AccountManagerTests.swift`. Behavioral change. Suggested message: `Add account manager for multi-account session handling`.

---

## Self-Review

- **Spec coverage:** §5.2 step 6（トークンと DPoP 鍵を Keychain に per-DID 保存）と §8「全アカウントのセッションは Keychain にキャッシュ、`AccountManager` が現在アカウントを管理」を、`KeychainStorage` + `AccountStore` + `AccountManager` で満たす。トークン自動リフレッシュは spec §8 にあるが本プランのスコープ外（Plan 9b 以降）。
- **Placeholder scan:** TBD/TODO なし。`KeychainStorage` は headless テスト不可のためビルド検証（Task 1 Step 6 で明示）。それ以外は完全な TDD。
- **Type consistency:** `SecureStorage.set(_:for:)` / `data(for:)` / `remove(for:)`、`AccountStore.save/account(did:)/index()/setCurrent(did:)/remove(did:)`、`AccountManager.add(loginResult:handle:dpopPrivateKeyRaw:)/current()/allDIDs()/switchTo(did:)/remove(did:)`、`AccountError.unknownAccount/noCurrentAccount`、`PersistedAccount(loginResult:handle:dpopPrivateKeyRaw:)` を全タスクで同一名で使用。`OAuthLoginResult` のメンバ名（`did`/`pds`/`authorizationServerIssuer`/`tokens`）と `TokenResponse`（`accessToken`/`refreshToken`/`scope`/`sub`）は実装済みソースと一致。`noCurrentAccount` は本プランでは未使用だが、Plan 9b の「現在アカウント前提の API 呼び出し」で使うため定義のみ用意（YAGNI 抵触を避けるため、もし実装者が不要と判断したら削ってよい）。

> 実装注意: `AccountError.noCurrentAccount` は本プランのテストで行使されない。厳密な YAGNI を優先するなら定義しないでもよい。残す場合もテストは不要（Plan 9b で行使される）。

## Carry-forward to Plan 9b (browser impl + wiring + UI)

- `ASWebAuthenticationSession` を `BrowserAuthorizationSession` に適合させる Apple 実体（presentation anchor、キャンセルのエラー写像）。アプリターゲットに置く。
- DPoP 鍵: ログイン時に `P256.Signing.PrivateKey()` を生成 → `rawRepresentation` を `PersistedAccount.dpopPrivateKeyRaw` に保存。復元は `try P256.Signing.PrivateKey(rawRepresentation:)` → `CryptoKitDPoPProvider(privateKey:)`。
- `OAuthClient` を実コラボレータで組み立てる Apple 配線（`URLSessionHTTPClient` / `OAuthDiscovery(http:)` / `AuthorizationRequestService(sender:)` / `TokenService(sender:)` / `SecRandomBytesGenerator` / ASWebAuth ブラウザ / `crypto.sha256`）。生成した P256 鍵を保持して保存に回す。
- `KeychainStorage(service:)` の `service` はアプリ bundle id（`as.ason.Hoshidukiyo`）。Keychain 利用には Hardened Runtime + Keychain Sharing entitlement の確認が必要（Plan 9b で project.yml / entitlements を調整）。
- ログイン UI（handle 入力 → `login` 起動 → `AccountManager.add` → メインウィンドウ）と、`HoshidukiyoApp` が現在アカウント有無で Login/Main を出し分ける統合。
