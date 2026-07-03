import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The catalog's determinism rests on ImageDownsampler reading file:// URLs
/// (bundled sample images). This pins that capability.
final class ImageDownsamplerFileURLTests: XCTestCase {
    func testLoadsFileURL() async throws {
        // Write a tiny 4x4 PNG to a temp file.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-probe-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)

        let decoded = try await ImageDownsampler.shared.image(for: url, maxPixel: 8)
        XCTAssertEqual(decoded.cgImage.width, 4)
    }
}
