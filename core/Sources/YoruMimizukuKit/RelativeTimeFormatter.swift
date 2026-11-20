import Foundation

/// Renders a short relative timestamp for a post, given an explicit `now` so it
/// is deterministic and testable: "now", "30s", "2m", "3h", "2d", or in Japanese
/// (the macOS desktop prototype) "今", "30秒", "2分", "3時間", "2日".
public struct RelativeTimeFormatter: Sendable {
    public enum Style: Sendable { case compact, japanese }

    public let style: Style

    public init(style: Style = .compact) {
        self.style = style
    }

    public func string(for date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        let japanese = style == .japanese
        if seconds < 5 { return japanese ? "今" : "now" }
        if seconds < 60 { return japanese ? "\(seconds)秒" : "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return japanese ? "\(minutes)分" : "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return japanese ? "\(hours)時間" : "\(hours)h" }
        let days = hours / 24
        return japanese ? "\(days)日" : "\(days)d"
    }
}
