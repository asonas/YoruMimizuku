import Foundation
import BlueskyCore

public protocol NotificationReadService: Sendable {
    func unreadCount(for did: String) async throws -> Int
    func updateSeen(for did: String, through date: Date) async throws
}

/// App-wide read state. Each window contributes its account exactly once while open.
@MainActor
public final class NotificationUnreadStore: ObservableObject {
    private final class Account {
        var windows: Set<UUID> = []
        var lastCount: Int?
        var pending: Date?
        var acknowledged: Date?
        var request: Task<Bool, Never>?
        var poller: Task<Void, Never>?
    }

    @Published public private(set) var counts: [String: Int] = [:]
    private var accounts: [String: Account] = [:]
    private let service: any NotificationReadService
    private var interval: Duration = .seconds(30)

    public init(service: any NotificationReadService) {
        self.service = service
    }

    public func open(_ did: String, window: UUID) {
        let account = accounts[did] ?? Account()
        accounts[did] = account
        account.windows.insert(window)
        publish(account, for: did)
        if account.poller == nil { startPolling(account, for: did) }
    }

    public func close(_ did: String, window: UUID) {
        guard let account = accounts[did] else { return }
        account.windows.remove(window)
        publish(account, for: did)
        stopIfIdle(account)
    }

    public func forget(_ did: String) {
        let account = accounts.removeValue(forKey: did)
        account?.poller?.cancel()
        account?.request?.cancel()
        counts[did] = nil
    }

    public func setPollingInterval(_ value: Duration) {
        guard value > .zero, value != interval else { return }
        interval = value
        for (did, account) in accounts where account.poller != nil {
            account.poller?.cancel()
            startPolling(account, for: did)
        }
    }

    private func startPolling(_ account: Account, for did: String) {
        account.poller = Task { [weak self, interval] in
            var backoff = PollingBackoff(base: interval)
            while !Task.isCancelled {
                guard let ok = await self?.refresh(did) else { return }
                if ok { backoff.recordSuccess() } else { backoff.recordFailure() }
                do { try await Task.sleep(for: backoff.currentInterval) } catch { return }
            }
        }
    }

    private func stopIfIdle(_ account: Account) {
        if account.windows.isEmpty && account.pending == nil {
            account.poller?.cancel()
            account.poller = nil
        }
    }

    public func markDisplayed(_ did: String, through date: Date) async {
        guard let account = accounts[did], !account.windows.isEmpty,
              date > (account.acknowledged ?? .distantPast),
              date > (account.pending ?? .distantPast) else { return }
        account.pending = date
        await refresh(did)
    }

    @discardableResult
    public func refresh(_ did: String) async -> Bool {
        guard let account = accounts[did], !account.windows.isEmpty || account.pending != nil else { return false }
        if let request = account.request { return await request.value }
        let request = Task {
            defer {
                account.request = nil
                stopIfIdle(account)
            }
            repeat {
                guard !Task.isCancelled else { return false }
                let sent = await sendPending(account, for: did)
                guard accounts[did] === account else { return false }
                do {
                    account.lastCount = try await service.unreadCount(for: did)
                    guard accounts[did] === account else { return false }
                    publish(account, for: did)
                } catch {
                    return false
                }
                if !sent { return false }
                // Another window may have displayed a newer page while either request was in flight.
            } while account.pending != nil && !Task.isCancelled
            return true
        }
        account.request = request
        return await request.value
    }

    private func sendPending(_ account: Account, for did: String) async -> Bool {
        guard let boundary = account.pending else { return true }
        do {
            try await service.updateSeen(for: did, through: boundary)
            account.acknowledged = boundary
            if account.pending == boundary { account.pending = nil }
            return true
        } catch {
            return false
        }
    }

    private func publish(_ account: Account, for did: String) {
        let count = account.windows.isEmpty ? nil : account.lastCount
        if counts[did] != count { counts[did] = count }
    }
}
