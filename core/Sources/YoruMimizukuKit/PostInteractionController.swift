import Foundation

/// Drives the optimistic like / repost toggle shared by `TimelineViewModel` and
/// `ThreadViewModel`. It reads and writes posts through the two injected closures
/// so each view model keeps owning its own storage (an array vs a single focused
/// post); the toggle logic itself lives here once.
///
/// Flow: apply the optimistic change immediately, call the network, then either
/// confirm with the real record URI (on a fresh add) or roll back to the captured
/// original (on failure).
@MainActor
struct PostInteractionController {
    let interactor: PostInteracting
    /// Returns the current post for an id, or nil if it is no longer present.
    let currentPost: (String) -> PostDisplay?
    /// Persists an updated post back into the owning view model's state.
    let writePost: (PostDisplay) -> Void

    func toggleLike(_ id: String) async {
        guard let original = currentPost(id) else { return }
        if original.isLiked {
            applyOptimistic(id) { $0.applyOptimisticUnlike() }
            await run(remove: original.viewerLikeURI, original: original) { try await interactor.removeLike(recordURI: $0) }
        } else {
            applyOptimistic(id) { $0.applyOptimisticLike() }
            await runAdd(id, original: original,
                         add: { try await interactor.like(uri: original.id, cid: original.cid) },
                         confirm: { $0.viewerLikeURI = $1 })
        }
    }

    func toggleRepost(_ id: String) async {
        guard let original = currentPost(id) else { return }
        if original.isReposted {
            applyOptimistic(id) { $0.applyOptimisticUnrepost() }
            await run(remove: original.viewerRepostURI, original: original) { try await interactor.removeRepost(recordURI: $0) }
        } else {
            applyOptimistic(id) { $0.applyOptimisticRepost() }
            await runAdd(id, original: original,
                         add: { try await interactor.repost(uri: original.id, cid: original.cid) },
                         confirm: { $0.viewerRepostURI = $1 })
        }
    }

    private func applyOptimistic(_ id: String, _ transform: (inout PostDisplay) -> Void) {
        guard var post = currentPost(id) else { return }
        transform(&post)
        writePost(post)
    }

    /// Run a removal (unlike / unrepost); roll back to `original` on failure.
    private func run(remove recordURI: String?, original: PostDisplay, _ delete: (String) async throws -> Void) async {
        guard let recordURI else { return }
        do {
            try await delete(recordURI)
        } catch {
            writePost(original)
        }
    }

    /// Run an addition (like / repost); confirm the real record URI on success,
    /// roll back to `original` on failure.
    private func runAdd(
        _ id: String, original: PostDisplay,
        add: () async throws -> String,
        confirm: (inout PostDisplay, String) -> Void
    ) async {
        do {
            let recordURI = try await add()
            guard var post = currentPost(id) else { return }
            confirm(&post, recordURI)
            writePost(post)
        } catch {
            writePost(original)
        }
    }
}
