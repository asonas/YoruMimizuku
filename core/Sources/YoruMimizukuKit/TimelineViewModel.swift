import Foundation
import BlueskyCore

/// One fetched page of the timeline: the rows plus the cursor that fetches the
/// next (older) page. A nil `cursor` means there is nothing older to load.
public struct TimelinePage: Equatable, Sendable {
    public let posts: [PostDisplay]
    public let cursor: String?

    public init(posts: [PostDisplay], cursor: String?) {
        self.posts = posts
        self.cursor = cursor
    }
}

/// Loads a page of timeline rows as UI-ready `PostDisplay` values. Passing the
/// previous page's `cursor` fetches the next (older) page; passing `nil` fetches
/// the freshest page. The app provides the live implementation (authenticated
/// XRPC + mapping); tests inject a stub. Keeps `TimelineViewModel` free of
/// OS/network concerns.
public protocol TimelineLoading: Sendable {
    func loadPage(cursor: String?) async throws -> TimelinePage
}

/// Drives the timeline screen: holds the load state machine plus the pagination
/// cursor so the view can append older posts (infinite scroll) and merge fresh
/// ones on top (periodic refresh). `@MainActor` because it is bound to SwiftUI;
/// the network work happens inside the injected loader.
@MainActor
public final class TimelineViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded([PostDisplay])
        case failed(String)

        /// True while the initial load is in flight, used to disable controls.
        public var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    @Published public private(set) var state: State = .idle
    /// True while an older page is being appended, used to show a footer spinner
    /// and to coalesce repeated infinite-scroll triggers into one request.
    @Published public private(set) var isLoadingMore = false
    /// Count of posts newer than the last item the viewer saw on this tab. Drives
    /// the sidebar badge. Always 0 while the tab is active.
    @Published public private(set) var unreadCount = 0

    /// Cursor for the next older page; nil before the first load and once the
    /// feed has been exhausted.
    private var cursor: String?
    /// The head post id at the moment the tab was last seen; the unread boundary.
    private var lastSeenTopID: String?
    /// True while this tab is the selected one. Active tabs keep their unread at 0.
    private var isActive = false
    /// The running refresh loop, or nil when not polling.
    private var pollingTask: Task<Void, Never>?
    private let loader: TimelineLoading
    private let interactor: PostInteracting?
    private let tracer: SignpostTracing

    public init(
        loader: TimelineLoading,
        interactor: PostInteracting? = nil,
        tracer: SignpostTracing = NoopSignpostTracing()
    ) {
        self.loader = loader
        self.interactor = interactor
        self.tracer = tracer
    }

    /// Toggle the viewer's like on `post`, updating the row optimistically and
    /// reconciling with the network. No-op when no interactor was injected.
    public func toggleLike(_ post: PostDisplay) async {
        await controller?.toggleLike(post.id)
    }

    /// Toggle the viewer's repost on `post`, updating optimistically. No-op when no
    /// interactor was injected.
    public func toggleRepost(_ post: PostDisplay) async {
        await controller?.toggleRepost(post.id)
    }

    /// A controller bound to this view model's post storage, or nil without an
    /// injected interactor.
    private var controller: PostInteractionController? {
        guard let interactor else { return nil }
        return PostInteractionController(
            interactor: interactor,
            currentPost: { [weak self] id in self?.post(id: id) },
            writePost: { [weak self] post in self?.write(post) }
        )
    }

    private func post(id: String) -> PostDisplay? {
        posts.first { $0.id == id }
    }

    private func write(_ post: PostDisplay) {
        guard case var .loaded(posts) = state, let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
        state = .loaded(posts)
    }

    /// Convenience accessor for the currently loaded posts (empty otherwise).
    public var posts: [PostDisplay] {
        if case let .loaded(posts) = state { return posts }
        return []
    }

    /// Whether an older page can still be fetched.
    public var canLoadMore: Bool { cursor != nil }

    /// Load the freshest timeline page, moving through loading -> loaded/failed.
    /// Wrapped in a signposted interval so the end-to-end load time (network +
    /// decode + mapping) is visible in Instruments.
    public func load() async {
        let endInterval = tracer.beginInterval("Timeline load")
        state = .loading
        do {
            let page = try await loader.loadPage(cursor: nil)
            cursor = page.cursor
            state = .loaded(page.posts)
            onItemsChanged()
            endInterval("loaded \(page.posts.count) posts")
        } catch {
            SessionExpiry.reportIfExpired(error)
            state = .failed(String(describing: error))
            endInterval("failed")
        }
    }

    /// Append the next older page (infinite scroll). No-op unless we are in the
    /// loaded state, have a cursor, and no append is already in flight. Newly
    /// fetched posts already present (by id) are dropped so a shifting feed never
    /// duplicates a row.
    public func loadMore() async {
        guard case let .loaded(current) = state, !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await loader.loadPage(cursor: cursor)
            self.cursor = page.cursor
            // Appending older posts to the tail never moves the head, so the unread
            // boundary is unaffected; no onItemsChanged() needed here.
            state = .loaded(Self.merging(current, appending: page.posts))
        } catch {
            SessionExpiry.reportIfExpired(error)
            // Keep the existing rows; a later scroll or refresh can retry.
        }
    }

    /// Refresh the head of the feed, merging fresh posts above the current rows
    /// (deduplicated by id) without disturbing the loaded tail or the cursor. If
    /// nothing is loaded yet this behaves like `load()`. Failures are swallowed so
    /// a periodic refresh never replaces good content with an error screen.
    public func refresh() async {
        guard case let .loaded(current) = state else {
            await load()
            return
        }
        do {
            let page = try await loader.loadPage(cursor: nil)
            state = .loaded(Self.merging(page.posts, appending: current))
            onItemsChanged()
        } catch {
            SessionExpiry.reportIfExpired(error)
            // Keep showing the current feed.
        }
    }

    /// Start the periodic refresh loop if it is not already running (idempotent).
    /// The loop is owned by the view model, so it keeps running—and keeps
    /// accumulating the unread count—after the view that started it disappears.
    public func startPolling(every interval: Duration) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    /// True while the periodic refresh loop is running.
    public var isPolling: Bool { pollingTask != nil }

    /// Stop the refresh loop. Called when a filter tab is closed.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Mark every loaded post as seen: the head becomes the unread boundary and the
    /// count drops to zero. Called when the tab is shown.
    public func markSeen() {
        lastSeenTopID = posts.first?.id
        unreadCount = 0
    }

    /// Set whether this tab is the selected one. Activating marks it seen so the
    /// active tab never shows a badge for posts the viewer is looking at.
    public func setActive(_ active: Bool) {
        isActive = active
        if active { markSeen() }
    }

    /// Recompute the unread count after the post list changed. On the very first
    /// load (no boundary yet) the existing posts are treated as seen.
    private func onItemsChanged() {
        if lastSeenTopID == nil { lastSeenTopID = posts.first?.id }
        if isActive {
            markSeen()
        } else {
            unreadCount = UnreadCounter.unread(ids: posts.map(\.id), since: lastSeenTopID)
        }
    }

    /// Concatenate two post lists preserving order while keeping the first
    /// occurrence of each id, so merges never duplicate a row.
    private static func merging(_ head: [PostDisplay], appending tail: [PostDisplay]) -> [PostDisplay] {
        var seen = Set<String>()
        var result: [PostDisplay] = []
        result.reserveCapacity(head.count + tail.count)
        for post in head where seen.insert(post.id).inserted {
            result.append(post)
        }
        for post in tail where seen.insert(post.id).inserted {
            result.append(post)
        }
        return result
    }
}
