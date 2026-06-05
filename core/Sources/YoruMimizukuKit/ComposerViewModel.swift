import Foundation

/// Drives the composer sheet: holds the draft body and images, exposes the
/// grapheme-based character budget (Bluesky caps posts at 300 graphemes), and
/// submits through an injected `PostSubmitting`. Lives in the kit so its logic is
/// unit-tested without SwiftUI.
@MainActor
public final class ComposerViewModel: ObservableObject {
    public static let maxGraphemes = 300
    public static let maxImages = 4

    @Published public var text: String = ""
    @Published public var images: [ComposeImage] = []
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var errorMessage: String?

    public let replyParentURI: String?
    /// Called after a successful submit so the view can dismiss and refresh.
    public var onPosted: (() -> Void)?

    private let submitter: PostSubmitting

    public init(submitter: PostSubmitting, replyParentURI: String? = nil) {
        self.submitter = submitter
        self.replyParentURI = replyParentURI
    }

    /// Grapheme-cluster count (not UTF-16 length) so emoji and combined marks count as one.
    public var graphemeCount: Int { text.count }
    public var remaining: Int { Self.maxGraphemes - graphemeCount }
    public var canAddImage: Bool { images.count < Self.maxImages }

    public var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard graphemeCount <= Self.maxGraphemes else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !images.isEmpty
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let draft = PostDraft(text: text, images: images, replyParentURI: replyParentURI)
        do {
            _ = try await submitter.submit(draft)
            isSubmitting = false
            onPosted?()
        } catch {
            isSubmitting = false
            errorMessage = String(describing: error)
        }
    }
}
