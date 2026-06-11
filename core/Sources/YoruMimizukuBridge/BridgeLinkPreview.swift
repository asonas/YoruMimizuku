#if canImport(WinSDK)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import YoruMimizukuKit

/// Process-wide OGP preview loader so repeated requests for the same URL share
/// one fetch and one cache entry, mirroring the macOS `LinkPreviews.shared`.
enum BridgeLinkPreviews {
    static let shared = LinkPreviewLoader(fetcher: BridgeHTMLFetcher())
}

/// Live `HTMLFetching` for Windows: a plain GET with a browser-ish Accept
/// header, a capped response size, and tolerant UTF-8 decoding. Only http(s)
/// URLs and HTML responses are accepted — everything else throws so the loader
/// caches the miss and the row keeps its tight layout.
struct BridgeHTMLFetcher: HTMLFetching {
    func fetchHTML(from url: URL) async throws -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let mime = http.mimeType, !mime.localizedCaseInsensitiveContains("html") {
            throw URLError(.cannotDecodeContentData)
        }
        // The OGP tags live in <head>; 1MB covers any sane page head while
        // keeping a huge document from ballooning memory.
        return String(decoding: data.prefix(1_000_000), as: UTF8.self)
    }

    private static let userAgent =
        "YoruMimizuku/0.8.0 (+https://tangled.org/asonas.tngl.sh/YoruMimizuku)"
}
#endif
