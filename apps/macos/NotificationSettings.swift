import SwiftUI

/// Holds the in-app notification preferences and persists them so they survive
/// launches: how often the badge-bearing tabs poll for new content, and whether
/// the sidebar shows unread badges at all. Shared via `environmentObject` so the
/// settings screen and the window's polling/badge wiring read the same values.
///
/// The Dock can show its unread count independently of the sidebar.
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

    @Published var showsDockBadge: Bool {
        didSet { defaults.set(showsDockBadge, forKey: Self.dockKey) }
    }

    /// The selectable polling intervals, in seconds.
    static let intervalChoices = [15, 30, 60, 300]
    static let defaultIntervalSeconds = 30

    private let defaults: UserDefaults
    private static let intervalKey = "notifications.pollIntervalSeconds"
    private static let badgesKey = "notifications.showsUnreadBadges"
    private static let dockKey = "notifications.showsDockBadge"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.object(forKey: Self.intervalKey) as? Int
        self.pollIntervalSeconds = storedInterval.map(Self.snapToChoice) ?? Self.defaultIntervalSeconds

        // Default to showing badges when nothing is stored.
        let sidebarEnabled = defaults.object(forKey: Self.badgesKey) as? Bool ?? true
        self.showsUnreadBadges = sidebarEnabled
        self.showsDockBadge = defaults.object(forKey: Self.dockKey) as? Bool ?? sidebarEnabled
        if defaults.object(forKey: Self.dockKey) == nil {
            defaults.set(sidebarEnabled, forKey: Self.dockKey)
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
