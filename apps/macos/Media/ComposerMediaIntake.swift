import Foundation

/// Abstraction over the parts of a pasteboard the composer reads when turning a
/// paste or a drop into image attachments. Keeping the intake logic behind this
/// protocol lets it be unit-tested without AppKit; `NSPasteboard` conforms in
/// `ComposerTextView.swift`.
protocol ComposerImageSource {
    /// Image file URLs present on the source (Finder copies / drags), already
    /// filtered to image content types by the adapter.
    func imageFileURLs() -> [URL]
    /// Raw image data items present on the source (screenshots, browser image
    /// copies) in priority order.
    func imageDataItems() -> [Data]
}

/// Turns pasteboard / drag contents into upload-ready image attachments, reusing
/// `ImageEncoder` for the ~1 MB blob limit.
enum ComposerMediaIntake {
    /// Encoded attachments for everything attachable on `source`. File URLs take
    /// precedence over raw data: a Finder drag exposes both a file URL and tiff
    /// data, and the file's original bytes (kept as-is when small) are preferable
    /// to a re-encoded tiff. Only when there are no image files do we fall back to
    /// raw data (a screenshot or a browser image copy, which has no file URL).
    static func attachments(from source: ComposerImageSource) -> [(data: Data, mimeType: String)] {
        let fileURLs = source.imageFileURLs()
        if !fileURLs.isEmpty {
            return fileURLs.compactMap(encode(url:))
        }
        return source.imageDataItems().compactMap(ImageEncoder.encodeForUpload(data:))
    }

    /// Cheap check for whether `source` carries anything attachable, used to drive
    /// the drop highlight without decoding/encoding the payload.
    static func canProvideImages(from source: ComposerImageSource) -> Bool {
        !source.imageFileURLs().isEmpty || !source.imageDataItems().isEmpty
    }

    private static func encode(url: URL) -> (data: Data, mimeType: String)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return ImageEncoder.encodeForUpload(url: url)
    }
}
