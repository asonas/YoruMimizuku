import SwiftUI

/// Holds the in-app notification preferences and persists them so they survive
/// launches: how often the badge-bearing tabs poll for new content, and whether
/// the sidebar shows unread badges at all. Shared via `environmentObject` so the
/// settings screen and the scene's polling/badge wiring read the same values.
///
/// OS notification banners and the app badge are out of scope here (planned for
/// a later release); this store only governs the app's own polling and badges.
/// Mirrors the macOS `NotificationSettingsStore` verbatim (no framework deps).
@MainActor
final class NotificationSettingsStore: ObservableObject {
    /// The polling interval in seconds. Restricted to `intervalChoices` so the
    /// picker stays a small, sensible set; a stored value outside the set is
    /// snapped to the nearest choice on load.
    @Published var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Self.intervalKey) }
    }

    /// Whether the sidebar shows unread/new badges on the home, notifications, and
    /// filter tabs. Polling still runs when this is off; only the badges are hidden.
    @Published var showsUnreadBadges: Bool {
        didSet { defaults.set(showsUnreadBadges, forKey: Self.badgesKey) }
    }

    /// The selectable polling intervals, in seconds.
    static let intervalChoices = [15, 30, 60, 300]
    static let defaultIntervalSeconds = 30

    private let defaults: UserDefaults
    private static let intervalKey = "notifications.pollIntervalSeconds"
    private static let badgesKey = "notifications.showsUnreadBadges"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.object(forKey: Self.intervalKey) as? Int
        self.pollIntervalSeconds = storedInterval.map(Self.snapToChoice) ?? Self.defaultIntervalSeconds

        // Default to showing badges when nothing is stored.
        if defaults.object(forKey: Self.badgesKey) == nil {
            self.showsUnreadBadges = true
        } else {
            self.showsUnreadBadges = defaults.bool(forKey: Self.badgesKey)
        }
    }

    /// The polling interval as a `Duration` for the view models' pollers.
    var pollInterval: Duration { .seconds(pollIntervalSeconds) }

    /// Snap an arbitrary seconds value to the nearest allowed choice, so a value
    /// persisted by an older build (or hand-edited) never leaves the picker blank.
    private static func snapToChoice(_ seconds: Int) -> Int {
        intervalChoices.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? defaultIntervalSeconds
    }
}
