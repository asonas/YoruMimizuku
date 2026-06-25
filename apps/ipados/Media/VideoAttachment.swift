import AVFoundation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers
import YoruMimizukuKit

/// A picked movie, received from `PhotosPicker` as a file URL copied into a temp
/// location so its bytes survive past the picker callback.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Loads a picked video file into a `ComposeVideo` (raw bytes + MIME + pixel
/// dimensions) plus a poster image for the composer thumbnail, using AVFoundation.
enum VideoAttachment {
    struct Loaded {
        let video: ComposeVideo
        let poster: UIImage?
    }

    static func load(url: URL) async -> Loaded? {
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

    private static func poster(for asset: AVURLAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let result = try? await generator.image(at: CMTime(seconds: 0, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: result.image)
    }
}
