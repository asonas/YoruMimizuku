import Foundation
import YoruMimizukuKit

/// File-backed `SavedFilterStoring`: persists a single account's filters to
/// `~/Library/Application Support/<bundle>/filters-<DID>.json`. The DID-scoped
/// filename keeps each signed-in account's filters separate. A future iCloud
/// store can replace this without touching `SavedFilterStore`.
struct FilterFileStore: SavedFilterStoring {
    let did: String
    private let directory: URL
    // FileManager is not Sendable, but its file operations are thread-safe and this
    // store conforms to the Sendable `SavedFilterStoring` port.
    nonisolated(unsafe) private let fileManager: FileManager

    init(did: String, fileManager: FileManager = .default) {
        self.did = did
        self.fileManager = fileManager
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent("as.ason.YoruMimizuku", isDirectory: true)
    }

    private var fileURL: URL {
        // DIDs contain ':' which is fine in a path component on APFS, but encode
        // it defensively so the filename stays portable.
        let safe = did.replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("filters-\(safe).json")
    }

    func load() throws -> [SavedFilter] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedFilter].self, from: data)
    }

    func save(_ filters: [SavedFilter]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(filters)
        try data.write(to: fileURL, options: .atomic)
    }
}
