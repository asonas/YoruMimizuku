import Foundation
import BlueskyCore

/// The data a conversation tab renders: the focused post (carrying its ancestor
/// chain via `replyParent`, unchanged from before) plus the child reply tree
/// below it. The app provides the live loader (authenticated XRPC + mapping);
/// tests inject a stub.
public struct ConversationThread: Equatable, Sendable {
    public let focus: PostDisplay
    public let replies: [ThreadNode]

    public init(focus: PostDisplay, replies: [ThreadNode]) {
        self.focus = focus
        self.replies = replies
    }
}

/// Loads a single post's thread as a `ConversationThread`: the focus's
/// `replyParent` is its immediate ancestor (recursively, when present), and
/// `replies` is the descendant tree below the focus.
public protocol ThreadLoading: Sendable {
    func loadThread(uri: String) async throws -> ConversationThread
}

/// Drives one conversation tab: loads the focused post (with its full ancestor chain
/// via `replyParent`) plus the descendant reply tree as a `ConversationThread`.
/// `@MainActor` because it is bound to SwiftUI; the network work happens in the
/// injected loader.
@MainActor
public final class ThreadViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(ConversationThread)
        case failed(String)

        public var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    @Published public private(set) var state: State = .idle

    /// The post as the opener already had it (a timeline row), shown in full
    /// until the thread arrives and kept if it fails, so only the replies wait.
    /// It is for reading only: its like and repost state may predate the
    /// viewer's latest change or come from another account's fetch, so likes
    /// and reposts act on the loaded thread.
    @Published public private(set) var preview: PostDisplay?

    /// Whether the reader uncovered the anchor's labeled media.
    @Published public var revealsMedia = false

    public let uri: String
    private let loader: ThreadLoading
    private let interactor: PostInteracting?

    public init(loader: ThreadLoading, uri: String, interactor: PostInteracting? = nil, preview: PostDisplay? = nil) {
        self.loader = loader
        self.uri = uri
        self.interactor = interactor
        self.preview = preview
    }

    /// The post to show as the conversation's anchor: the loaded thread's focus,
    /// or the preview until then.
    public var focus: PostDisplay? {
        if case let .loaded(thread) = state { return thread.focus }
        return preview
    }

    /// Supply the post for a page opened without it (a notification subject),
    /// once the same post is chosen from a row. A shown post is left alone.
    public func adoptPreview(_ post: PostDisplay) {
        guard focus == nil, post.id == uri else { return }
        preview = post
    }


    /// Toggle the viewer's like on the focused post, optimistically. No-op unless
    /// the post is loaded and an interactor was injected.
    public func toggleLike(_ post: PostDisplay) async {
        await controller?.toggleLike(post.id)
    }

    /// Toggle the viewer's repost on the focused post, optimistically.
    public func toggleRepost(_ post: PostDisplay) async {
        await controller?.toggleRepost(post.id)
    }

    private var controller: PostInteractionController? {
        guard let interactor else { return nil }
        return PostInteractionController(
            interactor: interactor,
            pending: pending,
            currentPost: { [weak self] id in self?.post(id: id) },
            writePost: { [weak self] post in self?.write(post) }
        )
    }

    /// Only the focused post is interactive in the conversation view; ancestor and
    /// reply nodes are re-anchor targets, so a non-matching id resolves to nil.
    private func post(id: String) -> PostDisplay? {
        guard case let .loaded(thread) = state, thread.focus.id == id else { return nil }
        return thread.focus
    }

    private func write(_ post: PostDisplay) {
        guard case let .loaded(thread) = state, thread.focus.id == post.id else { return }
        state = .loaded(ConversationThread(focus: post, replies: thread.replies))
    }

    /// Load the thread for `uri`, moving through loading -> loaded/failed. A load
    /// cancelled because its view went away (leaving the page in the detail pane)
    /// returns to idle, so showing the page again loads it instead of an error. A
    /// newer load supersedes an older one: the older one's late result is dropped.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        do {
            let fetch = pending.fetchStarted()
            defer { pending.fetchFinished(fetch) }
            let thread = try await loader.loadThread(uri: uri)
            guard generation == loadGeneration else { return }
            state = .loaded(ConversationThread(focus: pending.applied(to: thread.focus, fetch: fetch), replies: thread.replies))
        } catch {
            SessionExpiry.reportIfExpired(error)
            guard generation == loadGeneration else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = .idle
            } else {
                state = .failed(LoadFailure(error).message)
            }
        }
    }

    private var loadGeneration = 0
    private let pending = PendingInteractions()
}
