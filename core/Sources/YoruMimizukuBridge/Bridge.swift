#if canImport(WinSDK)
import Foundation
import Crypto
import BlueskyCore
import YoruMimizukuKit
import PlatformWindows

// MARK: - Errors

enum BridgeError: Error, CustomStringConvertible {
    case notInitialized
    case noCurrentAccount
    case invalidIssuer
    case unknownPendingLogin
    case message(String)

    var description: String {
        switch self {
        case .notInitialized: return "bridge not initialized (call yoru_init first)"
        case .noCurrentAccount: return "no current account"
        case .invalidIssuer: return "stored account has an invalid issuer URL"
        case .unknownPendingLogin: return "unknown or expired pending login"
        case let .message(text): return text
        }
    }
}

// MARK: - Service context (mirrors the macOS LiveServiceContext)

/// Per-request plumbing: restores the current account's DPoP key, builds the
/// DPoP-bound sender + metadata resolver, and persists tokens refreshed mid-call.
struct BridgeServiceContext {
    let account: PersistedAccount
    let issuer: URL
    let sender: DPoPRequestSender
    let metadataResolver: OAuthMetadataResolver
    let config: OAuthClientConfig
    private let accountManager: AccountManager

    init(accountManager: AccountManager, config: OAuthClientConfig) throws {
        guard let account = try accountManager.current() else { throw BridgeError.noCurrentAccount }
        guard let issuer = URL(string: account.issuer) else { throw BridgeError.invalidIssuer }
        let key = try P256.Signing.PrivateKey(rawRepresentation: account.dpopPrivateKeyRaw)
        let http = URLSessionHTTPClient()
        self.account = account
        self.issuer = issuer
        self.sender = DPoPRequestSender(
            http: http, proofBuilder: DPoPProofBuilder(crypto: CryptoKitDPoPProvider(privateKey: key))
        )
        self.metadataResolver = OAuthMetadataResolver(http: http)
        self.config = config
        self.accountManager = accountManager
    }

    func persist(_ refreshed: TokenResponse?) throws {
        guard let refreshed else { return }
        try accountManager.updateTokens(
            did: account.did,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? account.refreshToken,
            scope: refreshed.scope ?? account.scope
        )
    }
}

// MARK: - Pending login state (split for WebView2)

struct PendingLogin {
    let handle: String
    let verifier: String
    let state: String
    let dpopPrivateKeyRaw: Data
    let discovered: OAuthDiscovery.Result
}

// MARK: - Runtime

/// Process-wide bridge state, configured by `yoru_init`. Thread-safe because the
/// WinUI app calls bridge functions from background threads.
final class BridgeRuntime: @unchecked Sendable {
    nonisolated(unsafe) static var shared: BridgeRuntime?

    let accountManager: AccountManager
    let config: OAuthClientConfig

    private let lock = NSLock()
    private var pendingLogins: [String: PendingLogin] = [:]

    init(service: String, config: OAuthClientConfig) {
        self.accountManager = AccountManager(store: AccountStore(storage: DPAPISecureStorage(service: service)))
        self.config = config
    }

    func putPending(_ id: String, _ pending: PendingLogin) {
        lock.lock(); defer { lock.unlock() }
        pendingLogins[id] = pending
    }

    func takePending(_ id: String) -> PendingLogin? {
        lock.lock(); defer { lock.unlock() }
        return pendingLogins.removeValue(forKey: id)
    }

    static func require() throws -> BridgeRuntime {
        guard let shared else { throw BridgeError.notInitialized }
        return shared
    }
}
#endif
