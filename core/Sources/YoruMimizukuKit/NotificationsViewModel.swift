import Foundation
import BlueskyCore

/// Loads a page of notifications as UI-ready `NotificationDisplay` values. The app
/// provides the live implementation (authenticated XRPC + mapping); tests inject a
/// stub. Keeps `NotificationsViewModel` free of OS/network concerns.
public protocol NotificationsLoading: Sendable {
    func loadLatest() async throws -> [NotificationGroup]
}

/// Drives the notifications tab: holds the load state machine. `@MainActor`
/// because it is bound to SwiftUI; the network work happens inside the injected
/// loader.
@MainActor
public final class NotificationsViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded([NotificationGroup])
        case failed(String)

        public var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    @Published public private(set) var state: State = .idle
    /// Count of notification groups newer than the last the viewer saw. Drives the
    /// sidebar badge. Always 0 while the tab is active.
    @Published public private(set) var unreadCount = 0

    private var lastSeenTopID: String?
    private var isActive = false
    private var pollingTask: Task<Void, Never>?
    private let loader: NotificationsLoading

    public init(loader: NotificationsLoading) {
        self.loader = loader
    }

    /// Convenience accessor for the currently loaded notification groups (empty otherwise).
    public var items: [NotificationGroup] {
        if case let .loaded(items) = state { return items }
        return []
    }

    /// Load the latest notifications, moving through loading -> loaded/failed.
    /// Returns whether the fetch succeeded, so the polling loop can drive its backoff.
    @discardableResult
    public func load() async -> Bool {
        state = .loading
        do {
            let items = try await loader.loadLatest()
            state = .loaded(items)
            onItemsChanged()
            return true
        } catch {
            SessionExpiry.reportIfExpired(error)
            state = .failed(LoadFailure(error).message)
            return false
        }
    }

    /// Reload the notifications without flashing the loading state, so a periodic
    /// or manual refresh never replaces good content with a spinner. Failures keep
    /// the current list.
    /// Returns whether the fetch succeeded, so the polling loop can drive its backoff.
    @discardableResult
    public func refresh() async -> Bool {
        guard case .loaded = state else {
            return await load()
        }
        do {
            state = .loaded(try await loader.loadLatest())
            onItemsChanged()
            return true
        } catch {
            SessionExpiry.reportIfExpired(error)
            // Keep showing the current notifications.
            return false
        }
    }

    /// Start the periodic refresh loop if not already running (idempotent). Owned by
    /// the view model so it survives the view and keeps the badge fresh in the
    /// background.
    public func startPolling(every interval: Duration) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            var backoff = PollingBackoff(base: interval)
            let firstOK = await self?.load() ?? false
            if firstOK { backoff.recordSuccess() } else { backoff.recordFailure() }
            while !Task.isCancelled {
                try? await Task.sleep(for: backoff.currentInterval)
                if Task.isCancelled { break }
                let ok = await self?.refresh() ?? false
                if ok { backoff.recordSuccess() } else { backoff.recordFailure() }
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Mark every loaded notification as seen and reset the badge to zero.
    public func markSeen() {
        lastSeenTopID = items.first?.id
        unreadCount = 0
    }

    /// Set whether this tab is the selected one; activating marks it seen.
    public func setActive(_ active: Bool) {
        isActive = active
        if active { markSeen() }
    }

    /// Recompute the unread count; the first load's notifications are treated as seen.
    private func onItemsChanged() {
        if lastSeenTopID == nil { lastSeenTopID = items.first?.id }
        if isActive {
            markSeen()
        } else {
            unreadCount = UnreadCounter.unread(ids: items.map(\.id), since: lastSeenTopID)
        }
    }
}
