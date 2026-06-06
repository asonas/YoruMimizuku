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
    private var inFlight: [String: Task<TokenResponse, Error>] = [:]
    private var cache: [String: TokenResponse] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 8) {
        self.capacity = capacity
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

        let task = Task { try await perform() }
        inFlight[refreshToken] = task
        defer { inFlight[refreshToken] = nil }

        let result = try await task.value
        remember(refreshToken, result)
        return result
    }

    private func remember(_ key: String, _ value: TokenResponse) {
        if cache[key] == nil { order.append(key) }
        cache[key] = value
        while order.count > capacity {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}
