import Foundation

/// The likes and reposts the viewer changed and the server's copy may not show
/// yet, by post. A view model keeps one for as long as it lives:
/// - while a request is out, a second change of the same kind is ignored and a
///   fetched copy shows the change on top;
/// - once a request succeeds, fetches that started before it still show the
///   result, since their copy can predate it. The result is forgotten when the
///   last of those fetches finishes.
@MainActor
final class PendingInteractions {
    enum Kind: Hashable { case like, repost }

    private struct Key: Hashable {
        let id: String
        let kind: Kind
    }

    /// A finished change: its state, its record URI when turned on, and how many
    /// fetches had started when it finished.
    private struct Settled {
        let on: Bool
        let recordURI: String?
        let fetchesStarted: Int
    }

    /// Whether each request in flight turns the like or repost on.
    private var inFlight: [Key: Bool] = [:]
    private var settled: [Key: Settled] = [:]
    private var fetchesStarted = 0
    /// Fetches started and not yet finished, by their number.
    private var runningFetches: Set<Int> = []

    func contains(_ id: String, _ kind: Kind) -> Bool {
        inFlight[Key(id: id, kind: kind)] != nil
    }

    func begin(_ id: String, _ kind: Kind, turningOn on: Bool) {
        inFlight[Key(id: id, kind: kind)] = on
    }

    /// The request ended. `recordURI` is the result of a successful change:
    /// the new record (on) or nil (off); a failed request passes `succeeded: false`.
    func end(_ id: String, _ kind: Kind, succeeded: Bool, recordURI: String? = nil) {
        let key = Key(id: id, kind: kind)
        guard let on = inFlight.removeValue(forKey: key) else { return }
        // A failed request leaves the result of the one before it, if any.
        guard succeeded else { return }
        if runningFetches.isEmpty {
            settled[key] = nil
        } else {
            settled[key] = Settled(on: on, recordURI: recordURI, fetchesStarted: fetchesStarted)
        }
    }

    /// Call before each fetch whose posts go through `applied(to:fetch:)`, and
    /// `fetchFinished` with the result once that fetch can no longer apply.
    func fetchStarted() -> Int {
        fetchesStarted += 1
        runningFetches.insert(fetchesStarted)
        return fetchesStarted
    }

    func fetchFinished(_ fetch: Int) {
        runningFetches.remove(fetch)
        let oldestRunning = runningFetches.min() ?? .max
        settled = settled.filter { $0.value.fetchesStarted >= oldestRunning }
    }

    /// `post` as fetched by the fetch `fetch` (from `fetchStarted()`), with the
    /// viewer's changes the server's copy may not show applied on top. Nil
    /// `fetch` applies only the requests still in flight.
    func applied(to post: PostDisplay, fetch: Int?) -> PostDisplay {
        var post = post
        for kind in [Kind.like, .repost] {
            let key = Key(id: post.id, kind: kind)
            if let on = inFlight[key] {
                post.applyOptimistic(kind, on: on, recordURI: nil)
            } else if let fetch, let change = settled[key], fetch <= change.fetchesStarted {
                post.applyOptimistic(kind, on: change.on, recordURI: change.recordURI)
            }
        }
        return post
    }
}

private extension PostDisplay {
    mutating func applyOptimistic(_ kind: PendingInteractions.Kind, on: Bool, recordURI: String?) {
        switch (kind, on) {
        case (.like, true):
            applyOptimisticLike()
            if let recordURI { viewerLikeURI = recordURI }
        case (.like, false):
            applyOptimisticUnlike()
        case (.repost, true):
            applyOptimisticRepost()
            if let recordURI { viewerRepostURI = recordURI }
        case (.repost, false):
            applyOptimisticUnrepost()
        }
    }
}

/// Drives the optimistic like / repost changes shared by `TimelineViewModel` and
/// `ThreadViewModel`. It reads and writes posts through the two injected closures
/// so each view model keeps owning its own storage (an array vs a single focused
/// post); the logic itself lives here once.
///
/// Flow: apply the optimistic change immediately, call the network, then either
/// confirm with the real record URI (on a fresh add) or undo the change on the
/// post as it is by then (on failure), which may be a newer copy from a refresh.
@MainActor
struct PostInteractionController {
    let interactor: PostInteracting
    let pending: PendingInteractions
    /// Returns the current post for an id, or nil if it is no longer present.
    let currentPost: (String) -> PostDisplay?
    /// Persists an updated post back into the owning view model's state.
    let writePost: (PostDisplay) -> Void

    /// Like (`on`) or unlike the post. No-op when it is already in that state or
    /// a like change for it is still being sent.
    func setLike(_ id: String, on: Bool) async {
        guard !pending.contains(id, .like), let original = currentPost(id), original.isLiked != on else { return }
        pending.begin(id, .like, turningOn: on)
        if on {
            apply(id) { $0.applyOptimisticLike() }
            await add(id, .like,
                      add: { try await interactor.like(uri: original.id, cid: original.cid) },
                      confirm: { $0.viewerLikeURI = $1 },
                      undo: { post in
                          guard post.viewerLikeURI == PostDisplay.pendingLikeURI else { return }
                          post.applyOptimisticUnlike()
                      })
        } else {
            apply(id) { $0.applyOptimisticUnlike() }
            await remove(id, .like, recordURI: original.viewerLikeURI,
                         delete: { try await interactor.removeLike(recordURI: $0) },
                         undo: { post in
                             guard !post.isLiked else { return }
                             post.viewerLikeURI = original.viewerLikeURI
                             post.likeCount += 1
                         })
        }
    }

    /// Repost (`on`) or undo the repost. No-op when it is already in that state
    /// or a repost change for it is still being sent.
    func setRepost(_ id: String, on: Bool) async {
        guard !pending.contains(id, .repost), let original = currentPost(id), original.isReposted != on else { return }
        pending.begin(id, .repost, turningOn: on)
        if on {
            apply(id) { $0.applyOptimisticRepost() }
            await add(id, .repost,
                      add: { try await interactor.repost(uri: original.id, cid: original.cid) },
                      confirm: { $0.viewerRepostURI = $1 },
                      undo: { post in
                          guard post.viewerRepostURI == PostDisplay.pendingRepostURI else { return }
                          post.applyOptimisticUnrepost()
                      })
        } else {
            apply(id) { $0.applyOptimisticUnrepost() }
            await remove(id, .repost, recordURI: original.viewerRepostURI,
                         delete: { try await interactor.removeRepost(recordURI: $0) },
                         undo: { post in
                             guard !post.isReposted else { return }
                             post.viewerRepostURI = original.viewerRepostURI
                             post.repostCount += 1
                         })
        }
    }

    func toggleLike(_ id: String) async {
        guard let post = currentPost(id) else { return }
        await setLike(id, on: !post.isLiked)
    }

    func toggleRepost(_ id: String) async {
        guard let post = currentPost(id) else { return }
        await setRepost(id, on: !post.isReposted)
    }

    private func apply(_ id: String, _ transform: (inout PostDisplay) -> Void) {
        guard var post = currentPost(id) else { return }
        transform(&post)
        writePost(post)
    }

    /// Run a removal (unlike / unrepost); undo it on failure.
    private func remove(
        _ id: String, _ kind: PendingInteractions.Kind, recordURI: String?,
        delete: (String) async throws -> Void,
        undo: (inout PostDisplay) -> Void
    ) async {
        guard let recordURI else {
            pending.end(id, kind, succeeded: false)
            return
        }
        do {
            try await delete(recordURI)
            pending.end(id, kind, succeeded: true)
        } catch {
            pending.end(id, kind, succeeded: false)
            apply(id, undo)
        }
    }

    /// Run an addition (like / repost); confirm the real record URI on success,
    /// undo it on failure.
    private func add(
        _ id: String, _ kind: PendingInteractions.Kind,
        add: () async throws -> String,
        confirm: (inout PostDisplay, String) -> Void,
        undo: (inout PostDisplay) -> Void
    ) async {
        do {
            let recordURI = try await add()
            pending.end(id, kind, succeeded: true, recordURI: recordURI)
            apply(id) { confirm(&$0, recordURI) }
        } catch {
            pending.end(id, kind, succeeded: false)
            apply(id, undo)
        }
    }
}
