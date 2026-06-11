import XCTest
@testable import YoruMimizukuKit

final class LinkPreviewLoaderTests: XCTestCase {
    private actor FakeFetcher: HTMLFetching {
        var calls = 0
        var result: Result<String, Error>

        init(result: Result<String, Error>) {
            self.result = result
        }

        func fetchHTML(from url: URL) async throws -> String {
            calls += 1
            return try result.get()
        }
    }

    private let url = URL(string: "https://example.com/article")!

    func testLoadsAndParsesCard() async {
        let fetcher = FakeFetcher(result: .success(
            #"<meta property="og:title" content="Card"><meta property="og:description" content="desc">"#
        ))
        let loader = LinkPreviewLoader(fetcher: fetcher)

        let card = await loader.preview(for: url)

        XCTAssertEqual(card?.title, "Card")
        XCTAssertEqual(card?.description, "desc")
        XCTAssertEqual(card?.url, url)
    }

    func testCachesResultPerURL() async {
        let fetcher = FakeFetcher(result: .success(#"<meta property="og:title" content="Card">"#))
        let loader = LinkPreviewLoader(fetcher: fetcher)

        _ = await loader.preview(for: url)
        _ = await loader.preview(for: url)

        let calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
    }

    func testFetchFailureYieldsNilAndIsCached() async {
        let fetcher = FakeFetcher(result: .failure(URLError(.timedOut)))
        let loader = LinkPreviewLoader(fetcher: fetcher)

        let first = await loader.preview(for: url)
        let second = await loader.preview(for: url)

        XCTAssertNil(first)
        XCTAssertNil(second)
        let calls = await fetcher.calls
        XCTAssertEqual(calls, 1)
    }
}
