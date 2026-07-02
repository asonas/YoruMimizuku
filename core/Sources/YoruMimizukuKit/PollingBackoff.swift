import Foundation

/// Computes the wait between polling refreshes. Starts at a base interval and, as
/// consecutive refreshes keep failing (offline, HTTP 429, 5xx, ...), doubles the
/// wait each time so a struggling server or a rate limit is not hammered. Any
/// success snaps the wait straight back to the base interval.
///
/// A small pure value type so the doubling/cap/reset logic is unit-testable in
/// isolation from the timing-driven polling loops that consume it.
struct PollingBackoff {
    /// The wait used while polling is healthy, and the value reset to on success.
    let base: Duration
    /// The largest wait the backoff will ever produce: 300 seconds, or eight times
    /// the base interval when that is larger.
    let cap: Duration
    /// Number of consecutive failures since the last success.
    private(set) var failureCount = 0

    init(base: Duration) {
        self.base = base
        self.cap = max(.seconds(300), base * 8)
    }

    /// The wait before the next poll: `base * 2^failureCount`, clamped to `cap`.
    /// Doubling stops once `cap` is reached so a long failure streak never overflows.
    var currentInterval: Duration {
        var interval = base
        var doublings = 0
        while doublings < failureCount && interval < cap {
            interval = interval * 2
            doublings += 1
        }
        return min(interval, cap)
    }

    /// Record a successful poll: reset to the base interval.
    mutating func recordSuccess() {
        failureCount = 0
    }

    /// Record a failed poll: the next wait grows by another doubling (up to `cap`).
    mutating func recordFailure() {
        failureCount += 1
    }
}
