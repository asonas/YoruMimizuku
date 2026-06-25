import XCTest

final class ComposerMediaIntakeTests: XCTestCase {
    private struct FakeSource: ComposerImageSource {
        var urls: [URL] = []
        var data: [Data] = []
        func imageFileURLs() -> [URL] { urls }
        func imageDataItems() -> [Data] { data }
    }

    /// Small PNG (magic bytes + padding) under the limit, written to a temp file.
    private func writeTempPNG() throws -> URL {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 64))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try bytes.write(to: url)
        return url
    }

    /// An image file URL is encoded into an upload-ready attachment.
    func testImageFileURLProducesAttachment() throws {
        let url = try writeTempPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ComposerMediaIntake.attachments(from: FakeSource(urls: [url]))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.mimeType, "image/png")
    }

    /// A non-image file URL encodes to nothing and is dropped.
    func testNonImageFileURLIsExcluded() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ComposerMediaIntake.attachments(from: FakeSource(urls: [url]))

        XCTAssertTrue(result.isEmpty)
    }

    /// With no file URLs, raw image data is the fallback and is attached.
    func testRawImageDataFallback() {
        let jpeg = Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 64))

        let result = ComposerMediaIntake.attachments(from: FakeSource(data: [jpeg]))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.mimeType, "image/jpeg")
    }

    /// When both a file URL and raw data are present, the file URL wins and the
    /// raw data is not used (no double attach).
    func testFileURLTakesPrecedenceOverRawData() throws {
        let url = try writeTempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let jpeg = Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 64))

        let result = ComposerMediaIntake.attachments(from: FakeSource(urls: [url], data: [jpeg]))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.mimeType, "image/png")
    }

    /// An empty source yields no attachments, so the caller falls back to the
    /// default text paste.
    func testEmptySourceYieldsNothing() {
        let result = ComposerMediaIntake.attachments(from: FakeSource())

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(ComposerMediaIntake.canProvideImages(from: FakeSource()))
    }
}
