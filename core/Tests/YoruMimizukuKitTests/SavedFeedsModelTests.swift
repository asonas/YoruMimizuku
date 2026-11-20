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
            SavedFeedItem(id: "7", type: "somethingNew", value: "x", pinned: true),
            SavedFeedItem(id: "8", type: "feed", value: "at://f/b", pinned: true)
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

    /// Holds the first call until `release()`; `firstCallEntered()` returns once
    /// that call is waiting, so the test controls the completion order exactly.
    private actor FirstCallGatedLoader: SavedFeedsLoading {
        private var calls = 0
        private var gate: CheckedContinuation<Void, Never>?
        private var entered: CheckedContinuation<Void, Never>?
        let first: [SavedFeedSource]
        let later: [SavedFeedSource]
        init(first: [SavedFeedSource], later: [SavedFeedSource]) { self.first = first; self.later = later }

        func loadPinned() async throws -> [SavedFeedSource] {
            calls += 1
            guard calls == 1 else { return later }
            await withCheckedContinuation { continuation in
                gate = continuation
                entered?.resume()
                entered = nil
            }
            return first
        }

        func firstCallEntered() async {
            if gate != nil { return }
            await withCheckedContinuation { entered = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }

    func testAnOlderLoadFinishingLastDoesNotOverwriteANewerOne() async throws {
        let loader = FirstCallGatedLoader(first: [source("at://f/old")], later: [source("at://f/new")])
        let model = SavedFeedsModel(loader: loader, makeTimeline: { _ in TimelineViewModel(loader: StubTimelineLoader()) })

        let older = Task { await model.load() }
        await loader.firstCallEntered()
        await model.load()
        await loader.release()
        await older.value

        XCTAssertEqual(model.sources.map(\.id), ["at://f/new"])
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
