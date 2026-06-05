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

    /// Append a new filter built from typed terms. Returns nil (and does nothing)
    /// when the terms expand to no usable query. A blank name falls back to the
    /// joined subqueries as the label.
    @discardableResult
    public func add(name: String, terms: [FilterTerm], combinator: FilterCombinator) -> SavedFilter? {
        let candidate = SavedFilter(name: "", terms: terms, combinator: combinator)
        guard !candidate.subqueries.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? candidate.fallbackName : trimmedName
        let filter = SavedFilter(name: resolvedName, terms: terms, combinator: combinator)
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
