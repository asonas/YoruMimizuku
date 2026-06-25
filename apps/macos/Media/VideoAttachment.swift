import AVFoundation
import AppKit
import Foundation
import YoruMimizukuKit

/// Loads a picked video file into a `ComposeVideo` (raw bytes + MIME + pixel
/// dimensions) plus a poster image for the composer thumbnail. Reading the
/// dimensions and the poster frame uses AVFoundation, so this stays in the app
/// target rather than the platform-independent core.
enum VideoAttachment {
    struct Loaded {
        let video: ComposeVideo
        let poster: NSImage?
    }

    static func load(url: URL) async -> Loaded? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let asset = AVURLAsset(url: url)
        var width: Int?
        var height: Int?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let oriented = size.applying(transform)
            width = Int(abs(oriented.width).rounded())
            height = Int(abs(oriented.height).rounded())
        }

        let video = ComposeVideo(
            data: data, mimeType: mimeType(for: url), alt: "",
            filename: url.lastPathComponent, width: width, height: height
        )
        return Loaded(video: video, poster: await poster(for: asset))
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov", "qt": return "video/quicktime"
        default: return "video/mp4"
        }
    }

    private static func poster(for asset: AVURLAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        guard let result = try? await generator.image(at: CMTime(seconds: 0, preferredTimescale: 600)) else {
            return nil
        }
        return NSImage(cgImage: result.image, size: .zero)
    }
}
