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
        case failed(LoadFailure)

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
    /// Posts at the head that arrived after the viewer last saw the top of the
    /// list (the "新着 n 件" bar). Unlike `unreadCount` it does not reset when the
    /// tab is selected, only when the top is actually on screen.
    @Published public private(set) var newArrivals = 0
    /// The posts loaded when the top was last seen. The head posts not in it are
    /// new arrivals; a set rather than one marker, so deleting the post that was
    /// on top does not turn every older post into a new arrival.
    private var seenIDs: Set<String> = []
    /// Whether the first load has set `seenIDs` (which may legitimately be empty).
    private var hasSeenFirstLoad = false

    /// The id of the row that was at the top of the feed the last time it was
    /// scrolled. Survives the tab switch that tears the `FeedView` down (the view
    /// model outlives it), so returning to this tab restores the scroll position
    /// instead of snapping to the top. Deliberately not `@Published`: the feed
    /// updates it on every scroll, and republishing that churn would re-render the
    /// whole list. An id (not an offset) stays correct when a poll merges fresh
    /// posts above the current rows.
    public var scrollAnchorID: String?

    /// Cursor for the next older page; nil before the first load and once the
    /// feed has been exhausted.
    private var cursor: String?
    /// The head post id at the moment the tab was last seen; the unread boundary.
    private var lastSeenTopID: String?
    /// True while this tab is the selected one. Active tabs keep their unread at 0.
    private var isActive = false
    /// The running refresh loop, or nil when not polling.
    private var pollingTask: Task<Void, Never>?
    /// Bumped by every `load()`. A response belonging to an older load (one that a
    /// polling restart superseded) is dropped instead of replacing newer state.
    private var loadGeneration = 0
    /// Order of head-page requests (`load` and `refresh`). A head response older
    /// than the newest one already applied is dropped, so an earlier refresh that
    /// finishes last cannot push newer posts down.
    private var headRequestCount = 0
    private var appliedHeadRequest = 0
    /// Bumped whenever the rows are replaced (`load()` or a refresh that starts
    /// over). An older-page fetch from before that belongs to rows no longer
    /// shown: its page is dropped and it no longer holds `isLoadingMore`.
    private var pageGeneration = 0
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

    /// Repost (`on`) or undo the repost of `post`. Unlike a toggle, this does
    /// nothing when the post is already in that state by the time it runs.
    public func setRepost(_ post: PostDisplay, on: Bool) async {
        await controller?.setRepost(post.id, on: on)
    }

    /// Whether a repost change for `post` is still being sent.
    public func isSendingRepost(_ post: PostDisplay) -> Bool {
        pending.contains(post.id, .repost)
    }

    /// Delete the viewer's own `post`: remove its row immediately, then call the
    /// network. If the delete fails the row is restored at its original position so
    /// a transient error never silently drops a post the server still holds. No-op
    /// without an injected interactor or when the post is not in the loaded list.
    public func deletePost(_ post: PostDisplay) async {
        guard let interactor else { return }
        guard case let .loaded(current) = state,
              let index = current.firstIndex(where: { $0.id == post.id }) else { return }
        var pruned = current
        let removed = pruned.remove(at: index)
        state = .loaded(pruned)
        recountNewArrivals()
        do {
            try await interactor.deletePost(uri: post.id)
        } catch {
            guard case var .loaded(latest) = state else { return }
            latest.insert(removed, at: min(index, latest.count))
            state = .loaded(latest)
            recountNewArrivals()
        }
    }

    /// Authors the viewer muted while this timeline was open. Fetches already
    /// under way when they were muted are filtered too.
    private var hiddenAuthors: Set<String> = []

    private let pending = PendingInteractions()

    /// The posts of `fetch` (from `pending.fetchStarted()`) as shown: muted
    /// authors dropped, and the viewer's likes and reposts the server's copy may
    /// not show yet applied on top. Nil `fetch` re-filters posts already shown.
    private func visible(_ posts: [PostDisplay], fetch: Int? = nil) -> [PostDisplay] {
        let shown = hiddenAuthors.isEmpty ? posts : posts.filter { !hiddenAuthors.contains(ATURI.repo($0.id) ?? "") }
        return shown.map { pending.applied(to: $0, fetch: fetch) }
    }

    /// Drop every post by `did`, now and in later fetches, after the viewer muted
    /// that account. If the unread boundary sat on one of their posts it moves
    /// to the next remaining post, so the rest do not all turn unread.
    public func removePosts(byAuthor did: String) {
        hiddenAuthors.insert(did)
        guard case let .loaded(current) = state else { return }
        let kept = visible(current)
        // With no later post kept, the removed id stays the boundary: every
        // kept post is above it, which is what is unread.
        if let boundary = lastSeenTopID, !kept.contains(where: { $0.id == boundary }),
           let index = current.firstIndex(where: { $0.id == boundary }),
           let next = current[index...].first(where: { kept.contains($0) }) {
            lastSeenTopID = next.id
        }
        state = .loaded(kept)
        recountNewArrivals()
        if !isActive {
            unreadCount = UnreadCounter.unread(ids: kept.map(\.id), since: lastSeenTopID)
        }
    }

    /// A controller bound to this view model's post storage, or nil without an
    /// injected interactor.
    private var controller: PostInteractionController? {
        guard let interactor else { return nil }
        return PostInteractionController(
            interactor: interactor,
            pending: pending,
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
    /// Returns whether the fetch succeeded, so the polling loop can drive its backoff.
    @discardableResult
    public func load() async -> Bool {
        let endInterval = tracer.beginInterval("Timeline load")
        loadGeneration += 1
        let generation = loadGeneration
        headRequestCount += 1
        let request = headRequestCount
        state = .loading
        do {
            let fetch = pending.fetchStarted()
            defer { pending.fetchFinished(fetch) }
            let page = try await loader.loadPage(cursor: nil)
            guard generation == loadGeneration else { endInterval("superseded"); return true }
            appliedHeadRequest = request
            startNewPages()
            cursor = page.cursor
            state = .loaded(visible(page.posts, fetch: fetch))
            onItemsChanged()
            endInterval("loaded \(page.posts.count) posts")
            // A page made only of muted posts leaves no row to scroll to, so the
            // next page would never be requested; fetch it now.
            if posts.isEmpty, !page.posts.isEmpty, cursor != nil {
                await loadMore()
            }
            return true
        } catch {
            SessionExpiry.reportIfExpired(error)
            guard generation == loadGeneration else { endInterval("superseded"); return false }
            state = .failed(LoadFailure(error))
            endInterval("failed")
            return false
        }
    }

    /// Append the next older page (infinite scroll). No-op unless we are in the
    /// loaded state, have a cursor, and no append is already in flight. Newly
    /// fetched posts already present (by id) are dropped so a shifting feed never
    /// duplicates a row. The page is merged into the rows as they are when it
    /// arrives, so a head refresh that finished meanwhile is kept.
    public func loadMore() async {
        guard case .loaded = state, !isLoadingMore, let cursor else { return }
        let generation = pageGeneration
        isLoadingMore = true
        defer { if generation == pageGeneration { isLoadingMore = false } }
        do {
            let fetch = pending.fetchStarted()
            defer { pending.fetchFinished(fetch) }
            let page = try await loader.loadPage(cursor: cursor)
            guard generation == pageGeneration, case let .loaded(latest) = state else { return }
            self.cursor = page.cursor
            // Appending older posts to the tail never moves the head, so the unread
            // boundary is unaffected; no onItemsChanged() needed here. Older posts
            // are behind what was seen, so they never count as new arrivals.
            state = .loaded(Self.merging(latest, appending: visible(page.posts, fetch: fetch)))
            seenIDs.formUnion(page.posts.map(\.id))
        } catch {
            SessionExpiry.reportIfExpired(error)
            // Keep the existing rows; a later scroll or refresh can retry.
        }
    }

    /// Refresh the head of the feed, merging fresh posts above the current rows
    /// (deduplicated by id) without disturbing the loaded tail or the cursor,
    /// unless the fresh page shares no post with the rows held. If nothing is
    /// loaded yet this behaves like `load()`. Failures are swallowed so
    /// a periodic refresh never replaces good content with an error screen.
    /// Returns whether the fetch succeeded, so the polling loop can drive its backoff.
    @discardableResult
    public func refresh() async -> Bool {
        guard case .loaded = state else {
            return await load()
        }
        let generation = loadGeneration
        headRequestCount += 1
        let request = headRequestCount
        do {
            let fetch = pending.fetchStarted()
            defer { pending.fetchFinished(fetch) }
            let page = try await loader.loadPage(cursor: nil)
            // Merge into the rows as they are now, so an older page appended while
            // this request was in flight is kept.
            // A response superseded by a newer one still means the network is
            // fine, so it counts as a success for the polling backoff.
            guard generation == loadGeneration, request > appliedHeadRequest,
                  case let .loaded(latest) = state else { return true }
            appliedHeadRequest = request
            let held = Set(latest.map(\.id))
            if !page.posts.contains(where: { held.contains($0.id) }) {
                // The rows held (if any) no longer continue from this page, for
                // example after more than a page of new posts: start over from it
                // rather than leave a gap that scrolling could never fill, and
                // drop any older-page fetch still running for the old rows.
                startNewPages()
                cursor = page.cursor
                state = .loaded(Self.merging(visible(page.posts, fetch: fetch), appending: []))
            } else {
                state = .loaded(Self.merging(visible(page.posts, fetch: fetch), appending: latest))
            }
            onItemsChanged()
            return true
        } catch {
            SessionExpiry.reportIfExpired(error)
            // Keep showing the current feed.
            return false
        }
    }

    /// The rows are being replaced: forget any older-page fetch for the old ones.
    private func startNewPages() {
        pageGeneration += 1
        isLoadingMore = false
    }

    /// Start the periodic refresh loop if it is not already running (idempotent).
    /// The loop is owned by the view model, so it keeps running—and keeps
    /// accumulating the unread count—after the view that started it disappears.
    /// Restarting on a feed that is already loaded merges fresh posts on top
    /// instead of reloading, so older pages the reader scrolled into stay.
    public func startPolling(every interval: Duration) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            var backoff = PollingBackoff(base: interval)
            let firstOK = await self?.refresh() ?? false
            if firstOK { backoff.recordSuccess() } else { backoff.recordFailure() }
            while !Task.isCancelled {
                try? await Task.sleep(for: backoff.currentInterval)
                if Task.isCancelled { break }
                let ok = await self?.refresh() ?? false
                if ok { backoff.recordSuccess() } else { backoff.recordFailure() }
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

    /// The viewer has the top of the list on screen: everything loaded is seen.
    public func markHeadSeen() {
        seenIDs = Set(posts.map(\.id))
        newArrivals = 0
    }

    /// Count the head posts not seen at the top. The first load counts as seen.
    private func recountNewArrivals() {
        if !hasSeenFirstLoad {
            seenIDs = Set(posts.map(\.id))
            hasSeenFirstLoad = true
        }
        newArrivals = posts.prefix { !seenIDs.contains($0.id) }.count
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
        recountNewArrivals()
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
