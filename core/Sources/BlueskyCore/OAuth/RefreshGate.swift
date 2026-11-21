import Foundation

/// Serializes and coalesces OAuth `refresh_token` renewals, keyed by the (single-use)
/// refresh token. atproto rotates the refresh token on every use and immediately
/// invalidates the previous one, so concurrent pollers that each refresh with the
/// same snapshot token would have all-but-one rejected with `invalid_grant`.
///
/// The gate collapses concurrent renewals for one token into a single network call
/// and remembers the result, so a straggler still holding the now-consumed token
/// reuses the freshly issued tokens instead of replaying the dead one. A shared
/// instance must be used across all services for cross-tab coalescing to work.
public actor RefreshGate {
    /// Refresh tokens a renewal has used, readable without awaiting the actor so
    /// a synchronous save can tell a consumed token from a current one.
    private final class UsedTokens: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: Set<String> = []
        func insert(_ token: String) { lock.lock(); tokens.insert(token); lock.unlock() }
        func contains(_ token: String) -> Bool { lock.lock(); defer { lock.unlock() }; return tokens.contains(token) }
    }

    private let used = UsedTokens()
    private let onRenewed: (@Sendable (_ usedRefreshToken: String, _ issued: TokenResponse) -> Void)?
    private var inFlight: [String: Task<TokenResponse, Error>] = [:]
    private var cache: [String: TokenResponse] = [:]
    private var order: [String] = []
    private let capacity: Int

    /// `onRenewed` hears each renewal once, as it completes and before any
    /// caller gets the result, with the refresh token it used.
    public init(
        capacity: Int = 8,
        onRenewed: (@Sendable (_ usedRefreshToken: String, _ issued: TokenResponse) -> Void)? = nil
    ) {
        self.capacity = capacity
        self.onRenewed = onRenewed
    }

    /// Return renewed tokens for `refreshToken`, running `perform` at most once per
    /// token: a concurrent caller awaits the in-flight renewal, and a later caller
    /// reuses the cached result. Failures are not cached, so a genuinely dead token
    /// surfaces its error to every waiter and a fresh token can be tried later.
    public func refresh(
        using refreshToken: String,
        perform: @escaping @Sendable () async throws -> TokenResponse
    ) async throws -> TokenResponse {
        if let cached = cache[refreshToken] { return cached }
        if let task = inFlight[refreshToken] { return try await task.value }

        // Recorded inside the shared task, so a caller that joined it sees the
        // token as used (and the renewal reported) when it gets the result.
        let used = self.used
        let onRenewed = self.onRenewed
        let task = Task {
            let result = try await perform()
            used.insert(refreshToken)
            onRenewed?(refreshToken, result)
            return result
        }
        inFlight[refreshToken] = task
        defer { inFlight[refreshToken] = nil }

        let result = try await task.value
        remember(refreshToken, result)
        return result
    }

    /// Whether a renewal through this gate has already used `refreshToken`. The
    /// server invalidates a refresh token once used, so such a token must never
    /// be saved again.
    public nonisolated func hasUsed(_ refreshToken: String) -> Bool {
        used.contains(refreshToken)
    }

    private func remember(_ key: String, _ value: TokenResponse) {
        if cache[key] == nil { order.append(key) }
        cache[key] = value
        while order.count > capacity {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}
