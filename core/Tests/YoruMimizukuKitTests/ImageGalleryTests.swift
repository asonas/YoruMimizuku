import XCTest
@testable import YoruMimizukuKit

final class ImageGalleryTests: XCTestCase {
    private let urls = [
        URL(string: "https://cdn.example/1.jpg")!,
        URL(string: "https://cdn.example/2.jpg")!,
        URL(string: "https://cdn.example/3.jpg")!
    ]

    func testStartsAtRequestedIndex() {
        let gallery = ImageGallery(urls: urls, index: 1)
        XCTAssertEqual(gallery.index, 1)
        XCTAssertEqual(gallery.current, urls[1])
        XCTAssertEqual(gallery.count, 3)
    }

    func testClampsOutOfRangeStartIndex() {
        XCTAssertEqual(ImageGallery(urls: urls, index: 99).index, 2)
        XCTAssertEqual(ImageGallery(urls: urls, index: -5).index, 0)
    }

    func testGoNextAdvancesWithoutLooping() {
        var gallery = ImageGallery(urls: urls, index: 0)
        XCTAssertTrue(gallery.canGoNext)
        gallery.goNext()
        XCTAssertEqual(gallery.index, 1)
        gallery.goNext()
        XCTAssertEqual(gallery.index, 2)
        // At the last image, going next does nothing (no wrap-around).
        XCTAssertFalse(gallery.canGoNext)
        gallery.goNext()
        XCTAssertEqual(gallery.index, 2)
    }

    func testGoPreviousRewindsWithoutLooping() {
        var gallery = ImageGallery(urls: urls, index: 2)
        XCTAssertTrue(gallery.canGoPrevious)
        gallery.goPrevious()
        XCTAssertEqual(gallery.index, 1)
        gallery.goPrevious()
        XCTAssertEqual(gallery.index, 0)
        // At the first image, going previous does nothing (no wrap-around).
        XCTAssertFalse(gallery.canGoPrevious)
        gallery.goPrevious()
        XCTAssertEqual(gallery.index, 0)
    }

    func testSingleImageHasNoNavigation() {
        var gallery = ImageGallery(urls: [urls[0]], index: 0)
        XCTAssertFalse(gallery.canGoNext)
        XCTAssertFalse(gallery.canGoPrevious)
        gallery.goNext()
        gallery.goPrevious()
        XCTAssertEqual(gallery.index, 0)
    }
}
