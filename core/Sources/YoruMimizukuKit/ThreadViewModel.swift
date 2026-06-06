import Foundation
import BlueskyCore

/// Loads a single post's thread as a UI-ready `PostDisplay` whose `replyParent`
/// is the immediate ancestor (when present). The app provides the live
/// implementation (authenticated XRPC + mapping); tests inject a stub.
public protocol ThreadLoading: Sendable {
    func loadThread(uri: String) async throws -> PostDisplay
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
        case loaded(PostDisplay)
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

    /// Only the focused post is interactive in the conversation view; ancestors are
    /// re-anchor targets, so a non-matching id resolves to nil.
    private func post(id: String) -> PostDisplay? {
        guard case let .loaded(focus) = state, focus.id == id else { return nil }
        return focus
    }

    private func write(_ post: PostDisplay) {
        guard case let .loaded(focus) = state, focus.id == post.id else { return }
        state = .loaded(post)
    }

    /// Load the thread for `uri`, moving through loading -> loaded/failed.
    public func load() async {
        state = .loading
        do {
            let post = try await loader.loadThread(uri: uri)
            state = .loaded(post)
        } catch {
            SessionExpiry.reportIfExpired(error)
            state = .failed(String(describing: error))
        }
    }
}
