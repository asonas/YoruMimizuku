import Foundation
import CoreGraphics
import ImageIO
import YoruMimizukuKit
import PlatformApple

/// A decoded, already-downsampled image plus its memory cost for `NSCache`.
/// `@unchecked Sendable`: it wraps an immutable `CGImage` and is never mutated
/// after init, so it is safe to hand across the downsampler actor boundary.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    init(_ cgImage: CGImage) { self.cgImage = cgImage }
    /// Bytes the decoded bitmap occupies — used as the cache cost.
    var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Downloads and downsamples remote images, then caches the decoded bitmaps.
///
/// Replaces SwiftUI's `AsyncImage`, which keeps no decoded cache and decodes at
/// full resolution. Here ImageIO produces a thumbnail no larger than the display
/// size (`kCGImageSourceThumbnailMaxPixelSize`), so scrolling neither re-decodes
/// nor holds multi-megapixel bitmaps. Concurrent requests for the same key are
/// coalesced, and the work is wrapped in a `PerfSignpost.image` interval so the
/// download + decode time shows up in Instruments.
actor ImageDownsampler {
    static let shared = ImageDownsampler()

    private let cache = NSCache<NSString, DecodedImage>()
    private var inFlight: [NSString: Task<DecodedImage, Error>] = [:]
    private let session: URLSession

    enum ImageError: Error { case decodeFailed }

    init() {
        let config = URLSessionConfiguration.default
        let cacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("yorumimizuku-images", isDirectory: true)
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20, directory: cacheDirectory)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        cache.totalCostLimit = 64 << 20 // ~64 MB of decoded bitmaps
    }

    /// Returns a decoded image no larger than `maxPixel` on its longest edge,
    /// serving cache hits immediately and coalescing in-flight loads by key.
    func image(for url: URL, maxPixel: CGFloat) async throws -> DecodedImage {
        let key = "\(url.absoluteString)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task<DecodedImage, Error> { [session] in
            let signposter = PerfSignpost.image
            let interval = signposter.beginInterval("Load image")
            defer { signposter.endInterval("Load image", interval) }
            let (data, _) = try await session.data(from: url)
            return try Self.downsample(data: data, maxPixel: maxPixel)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let decoded = try await task.value
        cache.setObject(decoded, forKey: key, cost: decoded.cost)
        return decoded
    }

    /// Decodes `data` directly to a thumbnail bounded by `maxPixel`, never
    /// materializing the full-resolution bitmap.
    static func downsample(data: Data, maxPixel: CGFloat) throws -> DecodedImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageError.decodeFailed
        }
        return DecodedImage(cgImage)
    }
}
