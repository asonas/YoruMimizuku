import Foundation
import os

/// Loads a page of timeline rows as UI-ready `PostDisplay` values. The app
/// provides the live implementation (authenticated XRPC + mapping); tests inject
/// a stub. Keeps `TimelineViewModel` free of OS/network concerns.
public protocol TimelineLoading: Sendable {
    func loadLatest() async throws -> [PostDisplay]
}

/// Drives the timeline screen: holds the load state machine. `@MainActor` because
/// it is bound to SwiftUI; the network work happens inside the injected loader.
@MainActor
public final class TimelineViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded([PostDisplay])
        case failed(String)

        /// True while a load is in flight, used to disable the refresh control.
        public var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    @Published public private(set) var state: State = .idle

    private let loader: TimelineLoading

    public init(loader: TimelineLoading) {
        self.loader = loader
    }

    /// Convenience accessor for the currently loaded posts (empty otherwise).
    public var posts: [PostDisplay] {
        if case let .loaded(posts) = state { return posts }
        return []
    }

    /// Load the latest timeline page, moving through loading -> loaded/failed.
    /// Wrapped in a signposted interval so the end-to-end load time (network +
    /// decode + mapping) is visible in Instruments.
    public func load() async {
        let signposter = PerfSignpost.timeline
        let interval = signposter.beginInterval("Timeline load")
        state = .loading
        do {
            let posts = try await loader.loadLatest()
            state = .loaded(posts)
            signposter.endInterval("Timeline load", interval, "loaded \(posts.count) posts")
        } catch {
            state = .failed(String(describing: error))
            signposter.endInterval("Timeline load", interval, "failed")
        }
    }
}
