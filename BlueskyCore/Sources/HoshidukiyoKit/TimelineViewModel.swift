import Foundation
import os

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

    /// Cursor for the next older page; nil before the first load and once the
    /// feed has been exhausted.
    private var cursor: String?
    private let loader: TimelineLoading

    public init(loader: TimelineLoading) {
        self.loader = loader
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
        let signposter = PerfSignpost.timeline
        let interval = signposter.beginInterval("Timeline load")
        state = .loading
        do {
            let page = try await loader.loadPage(cursor: nil)
            cursor = page.cursor
            state = .loaded(page.posts)
            signposter.endInterval("Timeline load", interval, "loaded \(page.posts.count) posts")
        } catch {
            state = .failed(String(describing: error))
            signposter.endInterval("Timeline load", interval, "failed")
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
            state = .loaded(Self.merging(current, appending: page.posts))
        } catch {
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
        } catch {
            // Keep showing the current feed.
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
