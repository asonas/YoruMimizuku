import XCTest
@testable import YoruMimizukuKit

final class CatalogFixturesTests: XCTestCase {
    func testEveryVariantHasStableID() {
        XCTAssertEqual(CatalogVariant.postRowTwoImages.id, "PostRow/two-images")
        XCTAssertEqual(Set(CatalogVariant.allCases.map(\.id)).count,
                       CatalogVariant.allCases.count)
    }

    func testToastIsMacOnlyEverythingElseIsBoth() {
        for v in CatalogVariant.allCases {
            if v == .toast {
                XCTAssertEqual(v.platforms, [.macOS])
            } else {
                XCTAssertEqual(v.platforms, [.macOS, .iPadOS], v.id)
            }
        }
    }

    func testBundledImagesExistOnDisk() {
        for name in ["sample-wide", "sample-wide2", "sample-tall"] {
            let url = CatalogFixtures.imageURL(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
        }
    }

    func testFixturesAreDeterministic() {
        let a = CatalogFixtures.post(for: .postRowTwoImages)
        let b = CatalogFixtures.post(for: .postRowTwoImages)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.createdAt, b.createdAt)
        XCTAssertEqual(a.images.count, 2)
        // Sensitive fixture carries a warning; others don't.
        XCTAssertNotNil(CatalogFixtures.post(for: .postRowSensitive).mediaWarning)
    }
}
