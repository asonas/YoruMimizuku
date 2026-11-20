import Foundation

/// One of the viewer's curated lists and the list item that puts a given actor
/// on it (nil when the actor is not on it).
public struct CuratedListMembership: Equatable, Sendable {
    public let listURI: String
    public let name: String
    public let itemURI: String?

    public init(listURI: String, name: String, itemURI: String?) {
        self.listURI = listURI
        self.name = name
        self.itemURI = itemURI
    }
}

/// Reads and edits who is on the viewer's curated lists.
public protocol ListMembershipEditing: Sendable {
    /// The viewer's curated lists, each with `actorDID`'s list item if any.
    func lists(withMembershipOf actorDID: String) async throws -> [CuratedListMembership]
    /// Create a list item; returns its AT-URI.
    func add(actorDID: String, toList listURI: String) async throws -> String
    func remove(itemURI: String) async throws
}

/// The viewer's curated lists and a per-actor cache of who is on them, for the
/// "リストに追加" menu and for dropping a person on a list. A menu is built
/// synchronously, so it reads the cache. Changes run one at a time and re-read
/// the server first, because the PDS accepts duplicate list items; for the same
/// reason a change made here is trusted over a read for `recentWriteWindow`
/// seconds, while the appview has not indexed it yet. Share one instance per
/// account so its windows also take turns.
@MainActor
public final class ListMembershipModel: ObservableObject {
    public struct CuratedList: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public enum ListsState: Equatable, Sendable { case notLoaded, loaded, failed }

    public enum MembershipError: Error, Equatable {
        /// The server did not return the list (deleted, or past the first page),
        /// so membership cannot be checked before writing.
        case listNotFound
    }

    @Published public private(set) var lists: [CuratedList] = []
    /// Whether `lists` reflects the server. A failed reload after a successful
    /// one stays `loaded`, since the lists shown are still the viewer's.
    @Published public private(set) var listsState: ListsState = .notLoaded
    /// actor DID → list URI → list item URI, for the lists read for that actor.
    @Published private var items: [String: [String: String]] = [:]
    /// actor DID → the lists whose membership was read for that actor.
    @Published private var checked: [String: Set<String>] = [:]

    private let editor: ListMembershipEditing
    private let now: () -> Date
    private let recentWriteWindow: TimeInterval = 30
    private enum RecentWrite {
        case added(String)
        /// Keeps the removed item's URI: a read still returning that item is the
        /// removal not yet indexed, while a different item is a re-add elsewhere.
        case removed(String)
    }

    /// actor DID → list URI → the change this model just made.
    private var recentWrites: [String: [String: (write: RecentWrite, at: Date)]] = [:]
    /// Bumped per actor by every read and change, so a read that answers after a
    /// newer read or change does not overwrite it.
    private var generations: [String: Int] = [:]
    /// Reads are numbered when they start; `lists` takes a read's answer only if
    /// no later-started read has already filled it, so a later failure never
    /// discards an earlier success.
    private var readsStarted = 0
    private var listsFilledBy = 0
    private var fetchedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var isWriting = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    public init(editor: ListMembershipEditing, now: @escaping () -> Date = Date.init) {
        self.editor = editor
        self.now = now
    }

    /// Whether `actorDID` is on the list, or nil when that has not been read.
    public func isMember(_ actorDID: String, of listURI: String) -> Bool? {
        guard checked[actorDID]?.contains(listURI) == true else { return nil }
        return items[actorDID]?[listURI] != nil
    }

    /// Load the viewer's lists and `actorDID`'s membership. A failure keeps what
    /// is already cached.
    public func refresh(actorDID: String) async {
        do {
            try await fetch(actorDID)
        } catch {
            if listsState != .loaded { listsState = .failed }
        }
    }

    /// `refresh`, unless `actorDID` was read successfully within `maxAge`
    /// seconds or a read is under way. Used for prefetching, which can fire for
    /// every post a pointer rests on.
    public func refreshIfStale(actorDID: String, maxAge: TimeInterval = 60, now: Date = Date()) async {
        if let last = fetchedAt[actorDID], now.timeIntervalSince(last) < maxAge { return }
        guard inFlight.insert(actorDID).inserted else { return }
        defer { inFlight.remove(actorDID) }
        do {
            if try await fetch(actorDID).applied { fetchedAt[actorDID] = now }
        } catch {
            if listsState != .loaded { listsState = .failed }
        }
    }

    /// Put `actorDID` on the list or take them off it, writing only when the
    /// server is not already in that state. Returns whether anything was written.
    @discardableResult
    public func setMembership(_ actorDID: String, of listURI: String, to member: Bool) async throws -> Bool {
        await beginWrite()
        defer { endWrite() }
        let current = try await fetch(actorDID).memberships
        guard let target = current.first(where: { $0.listURI == listURI }) else {
            throw MembershipError.listNotFound
        }
        if member, target.itemURI == nil {
            let created = try await editor.add(actorDID: actorDID, toList: listURI)
            record(actorDID, listURI, .added(created))
            return true
        } else if !member, let itemURI = target.itemURI {
            try await editor.remove(itemURI: itemURI)
            record(actorDID, listURI, .removed(itemURI))
            return true
        }
        return false
    }

    /// Read the server and cache the answer, unless a newer read or change for
    /// the actor came first. Returns the answer with recent changes laid over it
    /// (used by a change to decide) and whether it was cached.
    @discardableResult
    private func fetch(_ actorDID: String) async throws -> (memberships: [CuratedListMembership], applied: Bool) {
        let generation = bumpGeneration(actorDID)
        readsStarted += 1
        let readNumber = readsStarted
        let answer = try await editor.lists(withMembershipOf: actorDID)
        let memberships = overlayRecentWrites(actorDID, on: answer)
        if readNumber > listsFilledBy {
            listsFilledBy = readNumber
            lists = memberships.map { CuratedList(id: $0.listURI, name: $0.name) }
            listsState = .loaded
        }
        guard generations[actorDID] == generation else { return (memberships, false) }
        var byList: [String: String] = [:]
        for membership in memberships {
            if let item = membership.itemURI { byList[membership.listURI] = item }
        }
        items[actorDID] = byList
        checked[actorDID] = Set(memberships.map(\.listURI))
        return (memberships, true)
    }

    private func overlayRecentWrites(_ actorDID: String, on answer: [CuratedListMembership]) -> [CuratedListMembership] {
        let cutoff = now().addingTimeInterval(-recentWriteWindow)
        let recent = (recentWrites[actorDID] ?? [:]).filter { $0.value.at > cutoff }
        recentWrites[actorDID] = recent
        guard !recent.isEmpty else { return answer }
        return answer.map { membership in
            guard let change = recent[membership.listURI]?.write else { return membership }
            let item: String?
            switch change {
            case let .added(created):
                item = membership.itemURI ?? created
            case let .removed(removed):
                item = membership.itemURI == removed ? nil : membership.itemURI
            }
            return CuratedListMembership(listURI: membership.listURI, name: membership.name, itemURI: item)
        }
    }

    private func record(_ actorDID: String, _ listURI: String, _ change: RecentWrite) {
        bumpGeneration(actorDID)
        recentWrites[actorDID, default: [:]][listURI] = (change, now())
        switch change {
        case let .added(created): items[actorDID, default: [:]][listURI] = created
        case .removed: items[actorDID, default: [:]][listURI] = nil
        }
        checked[actorDID, default: []].insert(listURI)
    }

    @discardableResult
    private func bumpGeneration(_ actorDID: String) -> Int {
        let next = (generations[actorDID] ?? 0) + 1
        generations[actorDID] = next
        return next
    }

    private func beginWrite() async {
        if isWriting {
            await withCheckedContinuation { writeWaiters.append($0) }
        } else {
            isWriting = true
        }
    }

    private func endWrite() {
        if writeWaiters.isEmpty {
            isWriting = false
        } else {
            writeWaiters.removeFirst().resume()
        }
    }
}
