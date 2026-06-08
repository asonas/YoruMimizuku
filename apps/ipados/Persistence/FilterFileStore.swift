import Foundation
import YoruMimizukuKit

struct FilterFileStore: SavedFilterStoring {
    let did: String
    private let directory: URL
    nonisolated(unsafe) private let fileManager: FileManager

    init(did: String, fileManager: FileManager = .default) {
        self.did = did
        self.fileManager = fileManager
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent("as.ason.YoruMimizukuPad", isDirectory: true)
    }

    private var fileURL: URL {
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
