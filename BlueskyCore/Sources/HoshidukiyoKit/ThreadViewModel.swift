import Foundation

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

    public init(loader: ThreadLoading, uri: String) {
        self.loader = loader
        self.uri = uri
    }

    /// Load the thread for `uri`, moving through loading -> loaded/failed.
    public func load() async {
        state = .loading
        do {
            let post = try await loader.loadThread(uri: uri)
            state = .loaded(post)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
