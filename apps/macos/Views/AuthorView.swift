import SwiftUI
import YoruMimizukuKit

/// One author tab's content: a profile header (avatar / display name / @handle /
/// bio) above the user's posts. The feed reuses `FeedView`, so j/k focus, infinite
/// scroll, and the post action affordances come along unchanged. View-only: there
/// is no follow or edit control. The header loads on appear; the feed is polled by
/// the window only while this tab is active.
struct AuthorView: View {
    let tab: AuthorTab
    @ObservedObject var header: ProfileHeaderViewModel
    @EnvironmentObject private var theme: ThemeStore

    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onOpenAuthor: (PostDisplay) -> Void
    var onReply: (PostDisplay) -> Void = { _ in }
    var onQuote: (PostDisplay) -> Void = { _ in }
    var onOpenQuote: (QuotedPost) -> Void = { _ in }
    /// The signed-in account's DID, forwarded to the feed so the viewer's own posts
    /// (visible when this is the viewer's own author tab) offer a delete action.
    var currentDID: String? = nil

    init(
        tab: AuthorTab,
        now: Date,
        onImageTap: @escaping ([URL], Int) -> Void,
        onOpenConversation: @escaping (PostDisplay) -> Void,
        onOpenAuthor: @escaping (PostDisplay) -> Void,
        onReply: @escaping (PostDisplay) -> Void = { _ in },
        onQuote: @escaping (PostDisplay) -> Void = { _ in },
        onOpenQuote: @escaping (QuotedPost) -> Void = { _ in },
        currentDID: String? = nil
    ) {
        self.tab = tab
        self.header = tab.header
        self.now = now
        self.onImageTap = onImageTap
        self.onOpenConversation = onOpenConversation
        self.onOpenAuthor = onOpenAuthor
        self.onReply = onReply
        self.onQuote = onQuote
        self.onOpenQuote = onOpenQuote
        self.currentDID = currentDID
    }

    var body: some View {
        VStack(spacing: 0) {
            profileHeader
            FeedView(
                model: tab.model, title: nil, showsHeader: false, now: now,
                onImageTap: onImageTap,
                onOpenConversation: onOpenConversation,
                onReply: onReply,
                onQuote: onQuote,
                onOpenAuthor: onOpenAuthor,
                onOpenQuote: onOpenQuote,
                currentDID: currentDID
            )
        }
        .background(theme.canvas)
        .task { await header.load() }
    }

    private var profileHeader: some View {
        let profile = header.profile
        let name = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: profile?.avatarURL ?? tab.avatarURL, maxPointSize: 56) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        theme.avatarPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text((name?.isEmpty == false ? name! : "@\(tab.handle)"))
                        .font(.app(.title3, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text("@\(profile?.handle ?? tab.handle)")
                        .font(.app(.callout))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }
}
