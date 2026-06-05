import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes images picked for a post so the uploaded bytes stay under Bluesky's
/// ~1 MB blob limit. Small originals pass through untouched; larger ones are
/// re-encoded as JPEG, dropping quality first and then pixel dimensions until the
/// result fits.
enum ImageEncoder {
    /// Bluesky rejects blobs larger than ~1 MB, so stay safely under that.
    static let maxBytes = 1_000_000

    private static let qualitySteps: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4]
    private static let pixelCaps: [CGFloat] = [2048, 1600, 1280, 1024, 768]

    /// Returns upload-ready bytes and their MIME type, or nil if the image can't
    /// be read or encoded.
    static func encodeForUpload(url: URL) -> (data: Data, mimeType: String)? {
        guard let original = try? Data(contentsOf: url) else { return nil }
        // Keep the original bytes when they already fit; only re-encode when needed.
        if original.count <= maxBytes {
            let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            return (original, mime)
        }
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        var smallest: Data?
        for cap in [CGFloat.greatestFiniteMagnitude] + pixelCaps {
            guard let image = scaled(full, longestSide: cap) else { continue }
            for quality in qualitySteps {
                guard let jpeg = jpegData(from: image, quality: quality) else { continue }
                if jpeg.count <= maxBytes { return (jpeg, "image/jpeg") }
                if smallest == nil || jpeg.count < smallest!.count { smallest = jpeg }
            }
        }
        // Couldn't get under the limit; hand back the smallest attempt so the
        // upload can still proceed (the server makes the final call).
        return smallest.map { ($0, "image/jpeg") }
    }

    /// Returns `image` scaled so its longest side is at most `longestSide`, or the
    /// original when it is already small enough.
    private static func scaled(_ image: CGImage, longestSide: CGFloat) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > longestSide else { return image }
        let factor = longestSide / longest
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
