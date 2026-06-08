import SwiftUI
import BlueskyCore
import YoruMimizukuKit

struct PostRowView: View {
    let post: PostDisplay
    var isFocused = false
    var onOpenThread: ((PostDisplay) -> Void)?
    var onOpenAuthor: ((String, String, String?, URL?) -> Void)?
    var onReply: ((PostDisplay) -> Void)?
    var onQuote: ((PostDisplay) -> Void)?
    var onToggleLike: ((PostDisplay) -> Void)?
    var onToggleRepost: ((PostDisplay) -> Void)?
    var onCopyPermalink: ((PostDisplay) -> Void)?
    var onOpenPermalink: ((PostDisplay) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if let did = ATURI.repo(post.id) {
                        onOpenAuthor?(did, post.authorHandle, post.authorDisplayName, post.avatarURL)
                    }
                } label: {
                    RemoteAvatar(url: post.avatarURL, size: 44)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(post.authorDisplayName.isEmpty ? post.authorHandle : post.authorDisplayName)
                            .font(.headline)
                        Text("@\(post.authorHandle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let label = post.contextLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(post.bodyAttributedString)
                        .font(.body)
                        .textSelection(.enabled)
                    imageGrid
                    actionBar
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isFocused ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onOpenThread?(post) }
    }

    @ViewBuilder
    private var imageGrid: some View {
        if !post.images.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(2, post.images.count)), spacing: 6) {
                ForEach(post.images) { image in
                    AsyncImage(url: image.thumbURL) { phase in
                        switch phase {
                        case let .success(content):
                            content.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                    .frame(height: post.images.count == 1 ? 260 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 22) {
            Button { onReply?(post) } label: {
                Label("\(post.replyCount)", systemImage: "bubble.left")
            }
            Button { onToggleRepost?(post) } label: {
                Label("\(post.repostCount)", systemImage: post.isReposted ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath")
            }
            Button { onToggleLike?(post) } label: {
                Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
            }
            Button { onQuote?(post) } label: {
                Image(systemName: "quote.bubble")
            }
            Button { onCopyPermalink?(post) } label: {
                Image(systemName: "link")
            }
            Button { onOpenPermalink?(post) } label: {
                Image(systemName: "safari")
            }
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

struct RemoteAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
