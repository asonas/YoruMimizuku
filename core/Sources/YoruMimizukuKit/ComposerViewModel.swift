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

    /// Progress phase while a post with a video is being sent: the video is
    /// uploaded, then the service processes it, before the record is created.
    public enum SubmitPhase: Equatable, Sendable {
        case idle
        case uploadingVideo
        case processingVideo
        case posting
    }

    @Published public var text: String = ""
    @Published public var images: [ComposeImage] = []
    /// The single attached video, exclusive with `images`.
    @Published public var video: ComposeVideo?
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var submitPhase: SubmitPhase = .idle
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
    /// Images and a video are mutually exclusive (atproto allows one media kind),
    /// so a video blocks adding images and vice versa.
    public var canAddImage: Bool { video == nil && images.count < Self.maxImages }
    public var canAddVideo: Bool { video == nil && images.isEmpty && !isSubmitting }

    public var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard graphemeCount <= Self.maxGraphemes else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A quote with no text is valid (quoting alone), and a video alone is also
        // a valid post, so each makes the draft submittable.
        return hasText || !images.isEmpty || video != nil || quotedPost != nil
    }

    /// Whether discarding the composer would lose something the user produced:
    /// non-blank text, attached images, or a video. Reply/quote targets alone
    /// don't count — reopening the composer recreates them.
    public var hasUnsavedContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty || video != nil
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let quote = quotedPost.map { StrongRef(uri: $0.id, cid: $0.cid) }
        // Trailing blank lines would be published verbatim, so drop them at the
        // submission boundary while leaving interior line breaks untouched.
        let trimmedText = PostText.trimmingTrailingWhitespace(of: text)
        let draft = PostDraft(text: trimmedText, images: images, video: video,
                              replyParentURI: replyParentURI, quote: quote)
        submitPhase = video == nil ? .posting : .uploadingVideo
        do {
            _ = try await submitter.submit(draft)
            isSubmitting = false
            submitPhase = .idle
            onPosted?()
        } catch {
            SessionExpiry.reportIfExpired(error)
            isSubmitting = false
            submitPhase = .idle
            errorMessage = String(describing: error)
        }
    }
}
