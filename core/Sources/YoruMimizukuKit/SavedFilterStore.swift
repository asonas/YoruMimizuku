import Foundation

/// Persistence port for saved filters. The app injects a concrete store
/// (currently a per-account Codable file); a future iCloud-backed implementation
/// can be swapped in without touching `SavedFilterStore`. Synchronous because the
/// backing stores are local and small.
public protocol SavedFilterStoring: Sendable {
    func load() throws -> [SavedFilter]
    func save(_ filters: [SavedFilter]) throws
}

/// Holds the user's saved filters and persists every mutation through the
/// injected port. `@MainActor` because it is bound to SwiftUI. CRUD is small and
/// synchronous; persistence failures are swallowed (filters are user preferences,
/// not critical state).
@MainActor
public final class SavedFilterStore: ObservableObject {
    @Published public private(set) var filters: [SavedFilter]

    private let port: SavedFilterStoring

    public init(port: SavedFilterStoring) {
        self.port = port
        self.filters = (try? port.load()) ?? []
    }

    /// Append a new filter. Returns nil (and does nothing) when the query is blank
    /// after trimming. A blank name falls back to the query as the label.
    @discardableResult
    public func add(name: String, query: String) -> SavedFilter? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = SavedFilter(
            name: trimmedName.isEmpty ? trimmedQuery : trimmedName,
            query: trimmedQuery
        )
        filters.append(filter)
        persist()
        return filter
    }

    /// Replace the filter sharing `edited.id` (no-op if absent), then persist.
    public func update(_ edited: SavedFilter) {
        guard let index = filters.firstIndex(where: { $0.id == edited.id }) else { return }
        filters[index] = edited
        persist()
    }

    /// Remove the filter with `id` (no-op if absent), then persist.
    public func remove(id: SavedFilter.ID) {
        let before = filters.count
        filters.removeAll { $0.id == id }
        if filters.count != before { persist() }
    }

    private func persist() {
        try? port.save(filters)
    }
}
