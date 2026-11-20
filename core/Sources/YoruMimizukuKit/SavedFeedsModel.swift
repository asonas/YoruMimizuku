import Foundation
import BlueskyCore

/// Fetches the account's pinned feeds and lists.
public protocol SavedFeedsLoading: Sendable {
    func loadPinned() async throws -> [SavedFeedSource]
}

/// The pinned feeds and lists shown in the macOS sidebar, each with its own
/// timeline. Pins are managed on the server (they sync across devices), so a
/// reload replaces the list; a feed that is no longer pinned stops polling.
@MainActor
public final class SavedFeedsModel: ObservableObject {
    @Published public private(set) var sources: [SavedFeedSource] = []

    private let loader: SavedFeedsLoading
    private let makeTimeline: @MainActor (SavedFeedSource) -> TimelineViewModel
    private var timelines: [String: TimelineViewModel] = [:]
    /// Bumped by every load so an older load that finishes last is dropped.
    private var loadGeneration = 0

    public init(loader: SavedFeedsLoading, makeTimeline: @escaping @MainActor (SavedFeedSource) -> TimelineViewModel) {
        self.loader = loader
        self.makeTimeline = makeTimeline
    }

    public var feeds: [SavedFeedSource] { sources.filter { $0.kind == .feed } }
    public var lists: [SavedFeedSource] { sources.filter { $0.kind == .list } }

    public func source(id: String) -> SavedFeedSource? {
        sources.first { $0.id == id }
    }

    /// Fetch the pins. A failure keeps the sources already shown.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        guard let loaded = try? await loader.loadPinned(), generation == loadGeneration else { return }
        let kept = Set(loaded.map(\.id))
        for (id, timeline) in timelines where !kept.contains(id) {
            timeline.stopPolling()
            timelines[id] = nil
        }
        sources = loaded
    }

    /// The timeline for a pinned source, created on first use. Nil for an id
    /// that is not pinned.
    public func timeline(for id: String) -> TimelineViewModel? {
        if let existing = timelines[id] { return existing }
        guard let source = source(id: id) else { return nil }
        let timeline = makeTimeline(source)
        timelines[id] = timeline
        return timeline
    }
}

/// A feed or list the account pinned (`savedFeedsPrefV2`), as the sidebar shows it.
public struct SavedFeedSource: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case feed, list }

    /// The feed generator's or list's AT-URI.
    public let id: String
    public let kind: Kind
    public let title: String
    public let description: String?
    public let creatorHandle: String?
    public let avatarURL: URL?

    public init(id: String, kind: Kind, title: String, description: String?, creatorHandle: String?, avatarURL: URL?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.description = description
        self.creatorHandle = creatorHandle
        self.avatarURL = avatarURL
    }

    /// The pinned feeds and lists in the order the account keeps them. The
    /// following timeline is the app's home tab, so it is skipped here, as are
    /// unpinned items, unknown kinds, items the server no longer resolves (a
    /// deleted feed or list), and repeats of a URI already listed.
    public static func pinned(from items: [SavedFeedItem], feeds: [FeedGeneratorView], lists: [ListView]) -> [SavedFeedSource] {
        let feedsByURI = Dictionary(feeds.map { ($0.uri, $0) }, uniquingKeysWith: { first, _ in first })
        let listsByURI = Dictionary(lists.map { ($0.uri, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let unique = items.filter { item in
            item.pinned && ["feed", "list"].contains(item.type) && seen.insert(item.value).inserted
        }
        return unique.compactMap { item in
            switch item.type {
            case "feed":
                guard let feed = feedsByURI[item.value] else { return nil }
                return SavedFeedSource(
                    id: feed.uri, kind: .feed, title: feed.displayName, description: feed.description,
                    creatorHandle: feed.creator.handle, avatarURL: feed.avatar.flatMap(URL.init(string:))
                )
            case "list":
                guard let list = listsByURI[item.value] else { return nil }
                return SavedFeedSource(
                    id: list.uri, kind: .list, title: list.name, description: list.description,
                    creatorHandle: list.creator.handle, avatarURL: list.avatar.flatMap(URL.init(string:))
                )
            default:
                return nil
            }
        }
    }
}
