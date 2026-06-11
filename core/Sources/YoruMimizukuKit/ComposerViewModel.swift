import Foundation
import BlueskyCore

/// Drives the composer sheet: holds the draft body and images, exposes the
/// grapheme-based character budget (Bluesky caps posts at 300 graphemes), and
/// submits through an injected `PostSubmitting`. Lives in the kit so its logic is
/// unit-tested without SwiftUI.
@MainActor
public final class ComposerViewModel: ObservableObject, Identifiable {
    public static let maxGraphemes = 300
    public static let maxImages = 4

    /// Stable identity so the composer can drive a `.sheet(item:)`. Marked
    /// `nonisolated` because `Identifiable`'s `id` requirement is nonisolated.
    nonisolated public let id = UUID()

    @Published public var text: String = ""
    @Published public var images: [ComposeImage] = []
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var errorMessage: String?

    /// The post being replied to, when the composer was opened from a post row.
    /// The full display model is kept for preview UI; submission still forwards
    /// only the post URI through `PostDraft`.
    public let replyParent: PostDisplay?
    private let explicitReplyParentURI: String?
    public var replyParentURI: String? { replyParent?.id ?? explicitReplyParentURI }
    /// The post being quoted, when this composer is a quote post. Shown as a
    /// preview and embedded as a record reference on submit.
    public let quotedPost: PostDisplay?
    /// Called after a successful submit so the view can dismiss and refresh.
    public var onPosted: (() -> Void)?

    private let submitter: PostSubmitting

    public init(
        submitter: PostSubmitting,
        replyParentURI: String? = nil,
        replyParent: PostDisplay? = nil,
        quotedPost: PostDisplay? = nil
    ) {
        self.submitter = submitter
        self.explicitReplyParentURI = replyParentURI
        self.replyParent = replyParent
        self.quotedPost = quotedPost
    }

    /// Grapheme-cluster count (not UTF-16 length) so emoji and combined marks count as one.
    public var graphemeCount: Int { text.count }
    public var remaining: Int { Self.maxGraphemes - graphemeCount }
    public var canAddImage: Bool { images.count < Self.maxImages }

    public var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard graphemeCount <= Self.maxGraphemes else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A quote with no text is valid (quoting alone), so the quoted post also
        // makes the draft submittable.
        return hasText || !images.isEmpty || quotedPost != nil
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let quote = quotedPost.map { StrongRef(uri: $0.id, cid: $0.cid) }
        // Trailing blank lines would be published verbatim, so drop them at the
        // submission boundary while leaving interior line breaks untouched.
        let trimmedText = PostText.trimmingTrailingWhitespace(of: text)
        let draft = PostDraft(text: trimmedText, images: images, replyParentURI: replyParentURI, quote: quote)
        do {
            _ = try await submitter.submit(draft)
            isSubmitting = false
            onPosted?()
        } catch {
            SessionExpiry.reportIfExpired(error)
            isSubmitting = false
            errorMessage = String(describing: error)
        }
    }
}
