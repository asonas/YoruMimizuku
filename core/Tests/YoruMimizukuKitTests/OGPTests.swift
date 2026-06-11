import XCTest
@testable import YoruMimizukuKit

final class OGPTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/blog/post")!

    func testParsesOpenGraphTags() {
        let html = """
        <html><head>
        <meta property="og:title" content="An Article">
        <meta property="og:description" content="Worth reading.">
        <meta property="og:image" content="https://cdn.example.com/hero.jpg">
        <title>fallback title</title>
        </head><body></body></html>
        """

        let card = OGP.parse(html: html, url: pageURL)

        XCTAssertEqual(card?.url, pageURL)
        XCTAssertEqual(card?.title, "An Article")
        XCTAssertEqual(card?.description, "Worth reading.")
        XCTAssertEqual(card?.thumbURL, URL(string: "https://cdn.example.com/hero.jpg"))
    }

    func testParsesReversedAttributeOrderAndSingleQuotes() {
        let html = """
        <meta content='Reversed' property='og:title'/>
        <meta content='https://cdn.example.com/i.png' property='og:image' />
        """

        let card = OGP.parse(html: html, url: pageURL)

        XCTAssertEqual(card?.title, "Reversed")
        XCTAssertEqual(card?.thumbURL, URL(string: "https://cdn.example.com/i.png"))
    }

    func testFallsBackToTitleTagAndMetaDescription() {
        let html = """
        <html><head>
        <title>Plain Title</title>
        <meta name="description" content="Plain description.">
        </head></html>
        """

        let card = OGP.parse(html: html, url: pageURL)

        XCTAssertEqual(card?.title, "Plain Title")
        XCTAssertEqual(card?.description, "Plain description.")
        XCTAssertNil(card?.thumbURL)
    }

    func testDecodesHTMLEntities() {
        let html = """
        <meta property="og:title" content="Q&amp;A &#x27;quoted&#x27; &lt;tag&gt; &#12354;">
        """

        let card = OGP.parse(html: html, url: pageURL)

        XCTAssertEqual(card?.title, "Q&A 'quoted' <tag> あ")
    }

    func testResolvesRelativeImageURL() {
        let html = """
        <meta property="og:title" content="t">
        <meta property="og:image" content="/images/hero.jpg">
        """

        let card = OGP.parse(html: html, url: pageURL)

        XCTAssertEqual(card?.thumbURL, URL(string: "https://example.com/images/hero.jpg"))
    }

    func testReturnsNilWithoutAnyTitle() {
        let html = "<html><body>no metadata here</body></html>"

        XCTAssertNil(OGP.parse(html: html, url: pageURL))
    }

    func testIgnoresWhitespaceAroundTitleTag() {
        let html = "<title>\n  Spaced Out \n</title>"

        XCTAssertEqual(OGP.parse(html: html, url: pageURL)?.title, "Spaced Out")
    }
}
