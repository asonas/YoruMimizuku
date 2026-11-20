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
/// synchronously, so it reads the cache; every write re-reads the server first,
/// because the cache can be stale and the PDS accepts duplicate list items.
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
    /// actor DID → list URI → list item URI.
    @Published private var items: [String: [String: String]] = [:]

    private let editor: ListMembershipEditing
    /// Bumped per actor by every read and write, so a read that answers after a
    /// newer read or write does not overwrite what that one cached.
    private var generations: [String: Int] = [:]
    private var fetchedAt: [String: Date] = [:]
    /// Changes run one at a time: a read-then-write is not atomic across its
    /// awaits, and two overlapping adds would both see "not on the list".
    private var isWriting = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    public init(editor: ListMembershipEditing) {
        self.editor = editor
    }

    /// Whether `actorDID` is on the list, or nil when not loaded yet.
    public func isMember(_ actorDID: String, of listURI: String) -> Bool? {
        items[actorDID].map { $0[listURI] != nil }
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

    /// `refresh`, unless `actorDID` was read within `maxAge` seconds. Used for
    /// prefetching, which can fire for every post a pointer rests on.
    public func refreshIfStale(actorDID: String, maxAge: TimeInterval = 60, now: Date = Date()) async {
        if let last = fetchedAt[actorDID], now.timeIntervalSince(last) < maxAge { return }
        fetchedAt[actorDID] = now
        await refresh(actorDID: actorDID)
    }

    /// Put `actorDID` on the list or take them off it, writing only when the
    /// server is not already in that state. Returns whether anything was written.
    @discardableResult
    public func setMembership(_ actorDID: String, of listURI: String, to member: Bool) async throws -> Bool {
        await beginWrite()
        defer { endWrite() }
        let current = try await fetch(actorDID)
        guard let target = current.first(where: { $0.listURI == listURI }) else {
            throw MembershipError.listNotFound
        }
        if member, target.itemURI == nil {
            let created = try await editor.add(actorDID: actorDID, toList: listURI)
            bumpGeneration(actorDID)
            items[actorDID, default: [:]][listURI] = created
            return true
        } else if !member, let itemURI = target.itemURI {
            try await editor.remove(itemURI: itemURI)
            bumpGeneration(actorDID)
            items[actorDID]?[listURI] = nil
            return true
        }
        return false
    }

    @discardableResult
    private func fetch(_ actorDID: String) async throws -> [CuratedListMembership] {
        let generation = bumpGeneration(actorDID)
        let memberships = try await editor.lists(withMembershipOf: actorDID)
        guard generations[actorDID] == generation else { return memberships }
        lists = memberships.map { CuratedList(id: $0.listURI, name: $0.name) }
        listsState = .loaded
        var byList: [String: String] = [:]
        for membership in memberships {
            if let item = membership.itemURI { byList[membership.listURI] = item }
        }
        items[actorDID] = byList
        return memberships
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
