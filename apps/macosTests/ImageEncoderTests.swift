import XCTest

final class ImageEncoderTests: XCTestCase {
    /// A GIF small enough to upload as-is should keep its bytes and report image/gif,
    /// so an animated GIF is not flattened into a static JPEG.
    func testGifUnderLimitPassesThroughAsGif() {
        let header: [UInt8] = Array("GIF89a".utf8)
        let data = Data(header + [UInt8](repeating: 0, count: 64))

        let result = ImageEncoder.encodeForUpload(data: data)

        XCTAssertEqual(result?.mimeType, "image/gif")
        XCTAssertEqual(result?.data, data)
    }

    /// A WebP small enough to upload as-is keeps its bytes and reports image/webp.
    func testWebPUnderLimitPassesThroughAsWebP() {
        var bytes: [UInt8] = Array("RIFF".utf8)
        bytes += [0, 0, 0, 0]              // RIFF chunk size (ignored here)
        bytes += Array("WEBP".utf8)
        bytes += [UInt8](repeating: 0, count: 32)
        let data = Data(bytes)

        let result = ImageEncoder.encodeForUpload(data: data)

        XCTAssertEqual(result?.mimeType, "image/webp")
        XCTAssertEqual(result?.data, data)
    }

    /// PNG still passes through untouched (regression).
    func testPngUnderLimitPassesThroughAsPng() {
        let data = Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 64))

        let result = ImageEncoder.encodeForUpload(data: data)

        XCTAssertEqual(result?.mimeType, "image/png")
        XCTAssertEqual(result?.data, data)
    }

    /// JPEG still passes through untouched (regression).
    func testJpegUnderLimitPassesThroughAsJpeg() {
        let data = Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 64))

        let result = ImageEncoder.encodeForUpload(data: data)

        XCTAssertEqual(result?.mimeType, "image/jpeg")
        XCTAssertEqual(result?.data, data)
    }

    /// Bytes that are neither a passthrough format nor a decodable image return nil.
    func testUndecodableBytesReturnNil() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])

        XCTAssertNil(ImageEncoder.encodeForUpload(data: data))
    }
}
