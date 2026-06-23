import XCTest
@testable import YoruMimizukuKit

final class TimelineLayoutTests: XCTestCase {
    func test_placement_isVerticalBelowThreshold() {
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 679), .vertical)
    }

    func test_placement_isReflowAtAndAboveThreshold() {
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 680), .reflow)
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 1200), .reflow)
    }

    func test_clampedSingleImageRatio_clampsTallToMinimum() {
        // tall image (portrait) ratio 0.45 -> clamped up to 0.8
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(0.45), 0.8, accuracy: 0.001)
    }

    func test_clampedSingleImageRatio_keepsModerateRatio() {
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(1.0), 1.0, accuracy: 0.001)
    }

    func test_clampedSingleImageRatio_clampsPanoramaToMaximum() {
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(8.0), 5.0, accuracy: 0.001)
    }

    func test_isTallCropped_trueWhenTallerThanCap() {
        XCTAssertTrue(TimelineLayout.isTallCropped(0.45))
    }

    func test_isTallCropped_falseAtOrAboveCap() {
        XCTAssertFalse(TimelineLayout.isTallCropped(0.8))
        XCTAssertFalse(TimelineLayout.isTallCropped(1.0))
    }
}
