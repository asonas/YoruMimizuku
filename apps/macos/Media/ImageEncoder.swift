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

    /// Returns upload-ready bytes and their MIME type for a file on disk, or nil if
    /// the image can't be read or encoded.
    static func encodeForUpload(url: URL) -> (data: Data, mimeType: String)? {
        guard let original = try? Data(contentsOf: url) else { return nil }
        return encodeForUpload(data: original)
    }

    /// Returns upload-ready bytes and their MIME type for raw image bytes (e.g. an
    /// image dropped from a browser or another app), or nil if the data isn't a
    /// readable image. PNG/JPEG that already fit pass through untouched; anything
    /// larger, or in another format, is re-encoded as JPEG until it fits.
    static func encodeForUpload(data original: Data) -> (data: Data, mimeType: String)? {
        // Keep the original bytes when they are an already-fitting PNG or JPEG; only
        // re-encode when too large or in a format Bluesky doesn't accept directly.
        if original.count <= maxBytes, let mime = passthroughMimeType(of: original) {
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

    /// The MIME type if `data` is a PNG or JPEG that may be uploaded as-is, detected
    /// by magic bytes. Returns nil for other formats so the caller re-encodes them.
    private static func passthroughMimeType(of data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return nil
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
