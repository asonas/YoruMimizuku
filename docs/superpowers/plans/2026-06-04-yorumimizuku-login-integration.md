# Login Integration Implementation Plan (Plan 9b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OAuth コアとアカウント永続化を実コラボレータでつなぎ、handle 入力からブラウザ認可・トークン取得・Keychain 保存・メインウィンドウ遷移までを行う、実際にビルド・起動できる macOS ログインを完成させる。

**Architecture:** プレゼンテーションロジック（`LoginViewModel` と `LoginPerforming` 抽象）は `YoruMimizukuKit` に置き、フェイク注入で状態遷移を TDD する。OS/アプリ依存（`ASWebAuthenticationSession` 実体、`OAuthClient` の実配線、SwiftUI ビュー、アプリ統合）はアプリターゲットに置き、`xcodebuild` のビルド成功で検証する（ブラウザ認可と Keychain の実挙動は人手で実機確認）。

**Tech Stack:** Swift 6, SwiftUI, AuthenticationServices (`ASWebAuthenticationSession`), CryptoKit (P-256), XCTest, XcodeGen。

**Scope note:** トークン自動リフレッシュとそのスケジューリング、Jetstream、タイムライン取得 API、通知は本プランのスコープ外。本プランは「ログインしてアカウントが Keychain に保存され、メインウィンドウが出る」までに限定する。実ログインの動作には外部前提として `https://ason.as/yorumimizuku/client-metadata.json` の公開が必要（§External Prerequisite 参照）。

---

## File Structure

- Create: `BlueskyCore/Sources/YoruMimizukuKit/LoginPerforming.swift` — ログイン実行の抽象 + 状態の値型。
- Create: `BlueskyCore/Sources/YoruMimizukuKit/LoginViewModel.swift` — ログイン画面の状態機械（`@MainActor` `ObservableObject`）。
- Test: `BlueskyCore/Tests/YoruMimizukuKitTests/LoginViewModelTests.swift`
- Create: `app/YoruMimizuku/Auth/ASWebAuthBrowserSession.swift` — `BrowserAuthorizationSession` の Apple 実体。
- Create: `app/YoruMimizuku/Auth/LiveLoginPerformer.swift` — `OAuthClient` 実配線 + `AccountManager` 保存。
- Create: `app/YoruMimizuku/Views/LoginView.swift` — handle 入力 + ログインボタン。
- Create: `app/YoruMimizuku/Views/RootView.swift` — 現在アカウント有無で Login/Main を出し分け。
- Modify: `app/YoruMimizuku/YoruMimizukuApp.swift` — `RootView` をホスト。
- Create: `docs/client-metadata.json` — 公開用 client-metadata の正本（ason.as へコピーする成果物）。

**Existing context to reuse (do NOT recreate):**
- BlueskyCore: `OAuthClient(discovery:authorizationRequester:tokenRequester:browser:random:sha256:config:)`, `OAuthLoginResult`, `OAuthDiscovery(http:)`, `DPoPRequestSender(http:proofBuilder:)`, `DPoPProofBuilder(crypto:)`, `AuthorizationRequestService(sender:)`, `TokenService(sender:)`, `CryptoKitDPoPProvider(privateKey:)` / `.sha256`, `SecRandomBytesGenerator`, `URLSessionHTTPClient`, `BrowserAuthorizationSession`, `OAuthClientConfig.yoruMimizuku`, `OAuthError`.
- Account: `KeychainStorage(service:)`, `AccountStore(storage:)`, `AccountManager(store:)`, `AccountManager.add(loginResult:handle:dpopPrivateKeyRaw:)`, `current()`.
- App: `MainWindowView`, `Theme`.
- `URLSessionHTTPClient` exact initializer — confirm in `BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift` before wiring (Task 3).

---

### Task 1: LoginViewModel state machine (YoruMimizukuKit, TDD)

**Files:**
- Create: `BlueskyCore/Sources/YoruMimizukuKit/LoginPerforming.swift`
- Create: `BlueskyCore/Sources/YoruMimizukuKit/LoginViewModel.swift`
- Test: `BlueskyCore/Tests/YoruMimizukuKitTests/LoginViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import YoruMimizukuKit

@MainActor
final class LoginViewModelTests: XCTestCase {
    private final class StubPerformer: LoginPerforming, @unchecked Sendable {
        var result: Result<String, Error>
        private(set) var receivedHandle: String?
        init(result: Result<String, Error>) { self.result = result }
        func login(handle: String) async throws -> String {
            receivedHandle = handle
            return try result.get()
        }
    }

    private struct StubError: Error {}

    func testInitialStateIsIdle() {
        let vm = LoginViewModel(performer: StubPerformer(result: .success("did:plc:a")))
        XCTAssertEqual(vm.state, .idle)
    }

    func testCannotSubmitWhenHandleBlank() {
        let vm = LoginViewModel(performer: StubPerformer(result: .success("did:plc:a")))
        vm.handle = "   "
        XCTAssertFalse(vm.canSubmit)
        vm.handle = "alice.bsky.social"
        XCTAssertTrue(vm.canSubmit)
    }

    func testSuccessfulSubmitReachesAuthenticated() async {
        let performer = StubPerformer(result: .success("did:plc:a"))
        let vm = LoginViewModel(performer: performer)
        vm.handle = "  alice.bsky.social  "
        await vm.submit()
        XCTAssertEqual(vm.state, .authenticated(did: "did:plc:a"))
        // Handle is trimmed before being passed to the performer.
        XCTAssertEqual(performer.receivedHandle, "alice.bsky.social")
    }

    func testFailedSubmitReachesFailedState() async {
        let vm = LoginViewModel(performer: StubPerformer(result: .failure(StubError())))
        vm.handle = "alice.bsky.social"
        await vm.submit()
        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
    }

    func testSubmitWithBlankHandleDoesNothing() async {
        let performer = StubPerformer(result: .success("did:plc:a"))
        let vm = LoginViewModel(performer: performer)
        vm.handle = "   "
        await vm.submit()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(performer.receivedHandle)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path BlueskyCore --filter LoginViewModelTests`
Expected: FAIL — `cannot find type 'LoginViewModel' / 'LoginPerforming' in scope`.

- [ ] **Step 3: Write minimal implementation**

`LoginPerforming.swift`:

```swift
import Foundation

/// Runs the full OAuth login for a handle and persists the resulting account,
/// returning the account DID. The app provides the live implementation; tests
/// inject a stub. Keeps `LoginViewModel` free of OS/network concerns.
public protocol LoginPerforming: Sendable {
    func login(handle: String) async throws -> String
}
```

`LoginViewModel.swift`:

```swift
import Foundation

/// Drives the login screen: holds the handle input and the login state machine.
/// `@MainActor` because it is bound to SwiftUI; the actual network/browser work
/// happens inside the injected `LoginPerforming`.
@MainActor
public final class LoginViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case authenticating
        case failed(String)
        case authenticated(did: String)
    }

    @Published public var handle: String = ""
    @Published public private(set) var state: State = .idle

    private let performer: LoginPerforming

    public init(performer: LoginPerforming) {
        self.performer = performer
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when there is a non-blank handle and no login is in flight.
    public var canSubmit: Bool {
        !trimmedHandle.isEmpty && state != .authenticating
    }

    /// Run the login. No-op when the handle is blank or a login is already running.
    public func submit() async {
        let account = trimmedHandle
        guard !account.isEmpty, state != .authenticating else { return }
        state = .authenticating
        do {
            let did = try await performer.login(handle: account)
            state = .authenticated(did: did)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path BlueskyCore --filter LoginViewModelTests`
Expected: PASS (5 cases).

- [ ] **Step 5: Run the full BlueskyCore suite**

Run: `swift test --package-path BlueskyCore`
Expected: all tests pass (93 prior + 5 new = 98).

- [ ] **Step 6: Commit**

Use the `/commit` skill (`git ai-commit`). Stage `LoginPerforming.swift` + `LoginViewModel.swift` + `LoginViewModelTests.swift`. Behavioral change. Suggested message: `Add login view model and login performer abstraction`.

---

### Task 2: ASWebAuthenticationSession browser implementation (app, build-validated)

**Files:**
- Create: `app/YoruMimizuku/Auth/ASWebAuthBrowserSession.swift`

(No unit test: `ASWebAuthenticationSession` requires a GUI and user interaction. Verified by `xcodebuild` in Task 5 and human run.)

- [ ] **Step 1: Write the implementation**

```swift
import Foundation
import AuthenticationServices
import AppKit
import BlueskyCore

/// `BrowserAuthorizationSession` backed by `ASWebAuthenticationSession`. Presents
/// the authorization URL in a secure system web view and resolves with the
/// redirect callback URL. Retains the in-flight session so it is not deallocated
/// before completion. `@unchecked Sendable`: all mutable state is touched only on
/// the main actor.
final class ASWebAuthBrowserSession: NSObject, BrowserAuthorizationSession,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {

    enum BrowserError: Error { case failedToStart, cancelled }

    private var activeSession: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: callbackScheme
                ) { [weak self] callbackURL, error in
                    self?.activeSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: BrowserError.cancelled)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.activeSession = session
                if !session.start() {
                    self.activeSession = nil
                    continuation.resume(throwing: BrowserError.failedToStart)
                }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
```

- [ ] **Step 2: Commit (after Task 5 confirms it builds, or commit now and build at the end)**

Commit with the app target in Task 5's build. Suggested message: `Add ASWebAuthenticationSession browser session`.

---

### Task 3: LiveLoginPerformer — real OAuthClient wiring (app, build-validated)

**Files:**
- Create: `app/YoruMimizuku/Auth/LiveLoginPerformer.swift`

- [ ] **Step 1: Confirm `URLSessionHTTPClient` initializer**

Read `BlueskyCore/Sources/BlueskyCore/Platform/URLSessionHTTPClient.swift` and note its initializer (likely `URLSessionHTTPClient()` or `URLSessionHTTPClient(session:)`). Use the real signature in Step 2.

- [ ] **Step 2: Write the implementation**

```swift
import Foundation
import CryptoKit
import BlueskyCore
import YoruMimizukuKit

/// Live `LoginPerforming`: generates a fresh DPoP P-256 key, wires the real
/// `OAuthClient` collaborators, runs the OAuth login, and persists the account
/// (with the DPoP key) via `AccountManager`. Returns the account DID.
struct LiveLoginPerformer: LoginPerforming {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func login(handle: String) async throws -> String {
        // One DPoP key for this account, used during login and persisted for reuse.
        let dpopKey = P256.Signing.PrivateKey()
        let crypto = CryptoKitDPoPProvider(privateKey: dpopKey)

        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))

        let client = OAuthClient(
            discovery: OAuthDiscovery(http: http),
            authorizationRequester: AuthorizationRequestService(sender: sender),
            tokenRequester: TokenService(sender: sender),
            browser: ASWebAuthBrowserSession(),
            random: SecRandomBytesGenerator(),
            sha256: { crypto.sha256($0) },
            config: config
        )

        let result = try await client.login(account: handle)
        let account = try accountManager.add(
            loginResult: result,
            handle: handle,
            dpopPrivateKeyRaw: dpopKey.rawRepresentation
        )
        return account.did
    }
}
```

> If `URLSessionHTTPClient()` is not the real initializer, adjust to the actual one found in Step 1. If `OAuthClient`'s `sha256` parameter requires `@Sendable`, the closure `{ crypto.sha256($0) }` captures the `Sendable` `crypto` struct and is fine.

- [ ] **Step 3: Commit**

Commit with Task 5's build. Suggested message: `Add live login performer wiring OAuth client to account manager`.

---

### Task 4: LoginView + RootView + app integration (app, build-validated)

**Files:**
- Create: `app/YoruMimizuku/Views/LoginView.swift`
- Create: `app/YoruMimizuku/Views/RootView.swift`
- Modify: `app/YoruMimizuku/YoruMimizukuApp.swift`

- [ ] **Step 1: Write LoginView**

```swift
import SwiftUI
import YoruMimizukuKit

/// The login screen: handle input and a sign-in button bound to `LoginViewModel`.
struct LoginView: View {
    @ObservedObject var model: LoginViewModel
    var onAuthenticated: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("YoruMimizuku").font(.title).bold().foregroundStyle(Theme.primaryText)
            Text("Bluesky にログイン").font(.callout).foregroundStyle(Theme.secondaryText)

            TextField("handle (例: alice.bsky.social)", text: $model.handle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .disabled(model.state == .authenticating)

            Button {
                Task {
                    await model.submit()
                    if case let .authenticated(did) = model.state { onAuthenticated(did) }
                }
            } label: {
                if model.state == .authenticating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("ログイン").bold()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)

            if case let .failed(message) = model.state {
                Text(message).font(.caption).foregroundStyle(.red).frame(width: 280)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
```

- [ ] **Step 2: Write RootView**

```swift
import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// Chooses the login screen or the main window based on whether an account is
/// currently stored. Builds the live login stack from the Keychain-backed store.
struct RootView: View {
    @State private var currentDID: String?
    @StateObject private var loginModel: LoginViewModel

    private let accountManager: AccountManager

    init() {
        let storage = KeychainStorage(service: "as.ason.YoruMimizuku")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        _currentDID = State(initialValue: (try? manager.current())??.did)
    }

    var body: some View {
        Group {
            if currentDID != nil {
                MainWindowView()
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
    }
}
```

> Note on `(try? manager.current())??.did`: `current()` returns `PersistedAccount?` and `try?` wraps it again to `PersistedAccount??`; `??.did` after flattening gives `String?`. If the compiler objects, write it explicitly:
> ```swift
> let existing = (try? manager.current()) ?? nil
> _currentDID = State(initialValue: existing?.did)
> ```
> Prefer the explicit two-line form for clarity.

- [ ] **Step 3: Update YoruMimizukuApp to host RootView**

```swift
import SwiftUI

@main
struct YoruMimizukuApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 420, height: 720)
    }
}
```

- [ ] **Step 4: Commit**

Commit with Task 5's build. Suggested message: `Add login and root views with account-gated navigation`.

---

### Task 5: Generate project, build & sign the app

**Files:**
- Create: `docs/client-metadata.json`
- (Regenerate `YoruMimizuku.xcodeproj` via XcodeGen.)

- [ ] **Step 1: Write the canonical client-metadata.json (artifact for ason.as)**

`docs/client-metadata.json`:

```json
{
  "client_id": "https://ason.as/yorumimizuku/client-metadata.json",
  "client_name": "YoruMimizuku",
  "application_type": "native",
  "dpop_bound_access_tokens": true,
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "scope": "atproto transition:generic",
  "redirect_uris": ["as.ason:/callback"],
  "token_endpoint_auth_method": "none"
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `cd /Users/asonas/workspace/yorumimizuku && xcodegen generate`
Expected: `Created project at YoruMimizuku.xcodeproj`. (New source files under `app/YoruMimizuku/Auth/` and `Views/` are picked up by the `sources: [app/YoruMimizuku]` glob.)

- [ ] **Step 3: Build the app**

Run:
```
xcodebuild build -project /Users/asonas/workspace/yorumimizuku/YoruMimizuku.xcodeproj \
  -scheme YoruMimizuku -configuration Debug \
  -derivedDataPath /Users/asonas/workspace/yorumimizuku/.worktrees/feature/login-integration/build/ \
  DEVELOPMENT_TEAM=QYP65434UW
```
Expected: `BUILD SUCCEEDED`. If signing fails, retry with `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO` to confirm compilation independently of signing, and report the signing error separately.

- [ ] **Step 4: Commit everything (app sources + project + client-metadata)**

Use the `/commit` skill. Stage `app/YoruMimizuku/Auth/ASWebAuthBrowserSession.swift`, `app/YoruMimizuku/Auth/LiveLoginPerformer.swift`, `app/YoruMimizuku/Views/LoginView.swift`, `app/YoruMimizuku/Views/RootView.swift`, `app/YoruMimizuku/YoruMimizukuApp.swift`, `docs/client-metadata.json`, and the regenerated `YoruMimizuku.xcodeproj` (note: `.gitignore` ignores `*.xcodeproj` — do NOT force-add it; the project is generated, project.yml is the source of truth). Behavioral change. Suggested message: `Wire login flow into the macOS app`.

> If Tasks 2/3/4 were not committed earlier, stage their files here too so the app target compiles as one coherent commit. Prefer one commit for the whole app-integration set since the files only compile together.

---

## Self-Review

- **Spec coverage:** §5.2 全体（handle → discovery → PAR → ブラウザ認可 → トークン交換 → Keychain 保存）が `LiveLoginPerformer` + `OAuthClient` + `AccountManager` で実機ログインとして成立。§3「夜フクロウ風単一カラム」は既存 `MainWindowView`、ログイン前は `LoginView`。§4 の OS touchpoint（ブラウザ = `ASWebAuthenticationSession`）を実装。
- **Placeholder scan:** TBD/TODO なし。app ターゲットの 4 ファイルは GUI/Keychain 依存のため `xcodebuild` ビルドで検証（明示）。`LoginViewModel` は TDD。
- **Type consistency:** `LoginPerforming.login(handle:) -> String`、`LoginViewModel.State`（idle/authenticating/failed/authenticated(did:)）、`LiveLoginPerformer.login(handle:)`、`OAuthClient(...)` の引数ラベル（discovery/authorizationRequester/tokenRequester/browser/random/sha256/config）、`AccountManager.add(loginResult:handle:dpopPrivateKeyRaw:)`、`CryptoKitDPoPProvider(privateKey:)` + `privateKey.rawRepresentation`、`KeychainStorage(service:)` は実装済みソースおよび Plan 8/9a と一致。

## External Prerequisite（実ログインに必須・コード外）

実際に Bluesky にログインするには、`client_id`（= `https://ason.as/yorumimizuku/client-metadata.json`）が公開 HTTPS 上に存在する必要がある。`docs/client-metadata.json` を ason.as リポジトリの `/yorumimizuku/client-metadata.json` として配置・デプロイすること。未配置だと認可サーバが client_id を解決できずログインは PAR 段で失敗する。リダイレクト `as.ason:/callback` は本アプリの `CFBundleURLSchemes`（`as.ason`、project.yml に既存）で受ける。

## Verification（人手・実機）

`xcodebuild` 成功後、`.app` を起動し、handle を入力 → ログイン → ブラウザで承認 → メインウィンドウ遷移、を確認する。Keychain 保存の確認は再起動後に `RootView` が `MainWindowView` を直接表示すること（`current()` が保存済みアカウントを返す）で行う。

## Carry-forward（後続）

- トークン期限切れ時の `TokenGrant.refresh` 自動実行と保存トークン更新（`AccountManager` に refresh を追加）。
- 保存済みアカウントの DPoP 鍵（`dpopPrivateKeyRaw`）を `P256.Signing.PrivateKey(rawRepresentation:)` で復元し、認証付き XRPC 呼び出しに再利用する配線。
- アカウント切替 UI（`accountChip` を実アカウント一覧に接続）、ログアウト（`AccountManager.remove`）。
- 読み取り API + `TimelineSource`（次フェーズ）。
