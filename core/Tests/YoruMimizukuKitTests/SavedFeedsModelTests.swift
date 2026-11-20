import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

// Test methods are `async` so swift-corelibs-xctest on Windows runs these
// `@MainActor` tests through its async invoker (see WorkspaceModelTests).
@MainActor
final class SavedFeedsModelTests: XCTestCase {
    private func generator(_ uri: String, _ name: String) -> FeedGeneratorView {
        FeedGeneratorView(
            uri: uri, creator: ProfileViewBasic(did: "did:plc:c", handle: "creator.example", displayName: nil, avatar: nil),
            displayName: name, description: "about \(name)", avatar: nil
        )
    }

    private func list(_ uri: String, _ name: String) -> ListView {
        ListView(
            uri: uri, name: name, description: nil, avatar: nil,
            creator: ProfileViewBasic(did: "did:plc:me", handle: "me.example", displayName: nil, avatar: nil)
        )
    }

    func testPinnedSourcesFollowTheSavedOrderAndSkipWhatTheSidebarCannotShow() async {
        let items = [
            SavedFeedItem(id: "1", type: "timeline", value: "following", pinned: true),
            SavedFeedItem(id: "2", type: "feed", value: "at://f/b", pinned: true),
            SavedFeedItem(id: "3", type: "list", value: "at://l/close", pinned: true),
            SavedFeedItem(id: "4", type: "feed", value: "at://f/a", pinned: true),
            SavedFeedItem(id: "5", type: "feed", value: "at://f/unpinned", pinned: false),
            SavedFeedItem(id: "6", type: "feed", value: "at://f/deleted", pinned: true),
            SavedFeedItem(id: "7", type: "somethingNew", value: "x", pinned: true)
        ]

        let sources = SavedFeedSource.pinned(
            from: items,
            feeds: [generator("at://f/a", "A"), generator("at://f/b", "B")],
            lists: [list("at://l/close", "近しい人")]
        )

        XCTAssertEqual(sources.map(\.id), ["at://f/b", "at://l/close", "at://f/a"])
        XCTAssertEqual(sources.map(\.kind), [.feed, .list, .feed])
        XCTAssertEqual(sources.map(\.title), ["B", "近しい人", "A"])
        XCTAssertEqual(sources.first?.creatorHandle, "creator.example")
        XCTAssertEqual(sources.first?.description, "about B")
    }

    private final class ScriptedLoader: SavedFeedsLoading, @unchecked Sendable {
        var results: [Result<[SavedFeedSource], Error>]
        init(_ results: [Result<[SavedFeedSource], Error>]) { self.results = results }
        func loadPinned() async throws -> [SavedFeedSource] { try results.removeFirst().get() }
    }

    private final class StubTimelineLoader: TimelineLoading, @unchecked Sendable {
        func loadPage(cursor: String?) async throws -> TimelinePage { TimelinePage(posts: [], cursor: nil) }
    }

    private struct StubError: Error {}

    private func source(_ id: String, _ kind: SavedFeedSource.Kind = .feed) -> SavedFeedSource {
        SavedFeedSource(id: id, kind: kind, title: id, description: nil, creatorHandle: nil, avatarURL: nil)
    }

    private func makeModel(_ loader: ScriptedLoader) -> SavedFeedsModel {
        SavedFeedsModel(loader: loader, makeTimeline: { _ in TimelineViewModel(loader: StubTimelineLoader()) })
    }

    func testAFailedReloadKeepsTheSourcesAlreadyShown() async {
        let model = makeModel(ScriptedLoader([.success([source("at://f/a")]), .failure(StubError())]))

        await model.load()
        await model.load()

        XCTAssertEqual(model.sources.map(\.id), ["at://f/a"])
    }

    func testTheSameSourceAlwaysGetsTheSameTimeline() async throws {
        let model = makeModel(ScriptedLoader([.success([source("at://f/a")])]))
        await model.load()

        let first = try XCTUnwrap(model.timeline(for: "at://f/a"))
        let second = try XCTUnwrap(model.timeline(for: "at://f/a"))

        XCTAssertTrue(first === second)
        XCTAssertNil(model.timeline(for: "at://f/unknown"))
    }

    func testASourceUnpinnedElsewhereStopsPollingAndIsDropped() async throws {
        let model = makeModel(ScriptedLoader([.success([source("at://f/a"), source("at://f/b")]), .success([source("at://f/b")])]))
        await model.load()
        let dropped = try XCTUnwrap(model.timeline(for: "at://f/a"))
        dropped.startPolling(every: .seconds(3600))

        await model.load()

        XCTAssertFalse(dropped.isPolling)
        XCTAssertNil(model.timeline(for: "at://f/a"))
        XCTAssertEqual(model.sources.map(\.id), ["at://f/b"])
    }
}
