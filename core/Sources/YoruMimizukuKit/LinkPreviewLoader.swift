import Foundation

/// Fetches a page's HTML for OGP extraction. The live implementation wraps
/// URLSession in the app; tests inject a fake so the loader stays unit-testable.
public protocol HTMLFetching: Sendable {
    func fetchHTML(from url: URL) async throws -> String
}

/// Builds `LinkCard`s for bare URLs by fetching the page and reading its OGP
/// tags. Results — including failures — are cached per URL for the loader's
/// lifetime, and concurrent requests for the same URL share one fetch, so a
/// URL that appears in many timeline rows is fetched at most once.
public actor LinkPreviewLoader {
    private let fetcher: HTMLFetching
    private var inFlight: [URL: Task<LinkCard?, Never>] = [:]

    public init(fetcher: HTMLFetching) {
        self.fetcher = fetcher
    }

    public func preview(for url: URL) async -> LinkCard? {
        if let task = inFlight[url] {
            return await task.value
        }
        let fetcher = self.fetcher
        let task = Task<LinkCard?, Never> {
            guard let html = try? await fetcher.fetchHTML(from: url) else { return nil }
            return OGP.parse(html: html, url: url)
        }
        inFlight[url] = task
        return await task.value
    }
}
