import Foundation

/// Renders a short relative timestamp ("now", "30s", "2m", "3h", "2d") for a
/// post, given an explicit `now` so it is deterministic and testable.
public struct RelativeTimeFormatter: Sendable {
    public init() {}

    public func string(for date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
