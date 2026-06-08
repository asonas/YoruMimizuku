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

/// Drives one conversation tab: fetches the focused post and its immediate parent
/// so the parent can be opened in a new tab, climbing the reply tree recursively.
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

    public let uri: String
    private let loader: ThreadLoading
    private let interactor: PostInteracting?

    public init(loader: ThreadLoading, uri: String, interactor: PostInteracting? = nil) {
        self.loader = loader
        self.uri = uri
        self.interactor = interactor
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
            currentPost: { [weak self] id in self?.post(id: id) },
            writePost: { [weak self] post in self?.write(post) }
        )
    }

    /// Only the focused post is interactive in the conversation view; reply nodes
    /// are re-anchor targets, so a non-matching id resolves to nil.
    private func post(id: String) -> PostDisplay? {
        guard case let .loaded(thread) = state, thread.focus.id == id else { return nil }
        return thread.focus
    }

    private func write(_ post: PostDisplay) {
        guard case let .loaded(thread) = state, thread.focus.id == post.id else { return }
        state = .loaded(ConversationThread(focus: post, replies: thread.replies))
    }

    /// Load the thread for `uri`, moving through loading -> loaded/failed.
    public func load() async {
        state = .loading
        do {
            let thread = try await loader.loadThread(uri: uri)
            state = .loaded(thread)
        } catch {
            SessionExpiry.reportIfExpired(error)
            state = .failed(String(describing: error))
        }
    }
}
