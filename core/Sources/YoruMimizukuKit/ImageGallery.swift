import Foundation

/// The set of full-size images shown in the lightbox plus the currently visible
/// index. Navigation clamps at both ends (no wrap-around): advancing past the
/// last image or rewinding before the first is a no-op, which the view uses to
/// disable the corresponding arrow key.
public struct ImageGallery: Equatable, Sendable {
    public let urls: [URL]
    public private(set) var index: Int

    public init(urls: [URL], index: Int) {
        self.urls = urls
        self.index = urls.isEmpty ? 0 : min(max(index, 0), urls.count - 1)
    }

    public var count: Int { urls.count }

    public var current: URL? { urls.indices.contains(index) ? urls[index] : nil }

    public var canGoNext: Bool { index < urls.count - 1 }

    public var canGoPrevious: Bool { index > 0 }

    public mutating func goNext() {
        guard canGoNext else { return }
        index += 1
    }

    public mutating func goPrevious() {
        guard canGoPrevious else { return }
        index -= 1
    }
}
