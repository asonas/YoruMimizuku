import SwiftUI
import HoshidukiyoKit

/// One timeline row, rendered compact (Yorufukurou-tight) or comfortable
/// (avatars + action counts) per `DisplayDensity`.
struct PostRowView: View {
    let post: PostDisplay
    let density: DisplayDensity
    let now: Date

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    var body: some View {
        switch density {
        case .compact:
            compactBody
        case .comfortable:
            comfortableBody
        }
    }

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                if let context = post.contextLabel {
                    Text(context).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 4) {
                    Text(post.authorDisplayName).font(.caption).bold().foregroundStyle(Theme.primaryText)
                    Text("@\(post.authorHandle) · \(relativeTime)").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
                Text(post.body).font(.callout).foregroundStyle(Theme.primaryText)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
    }

    private var comfortableBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                if let context = post.contextLabel {
                    Text(context).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 5) {
                    Text(post.authorDisplayName).font(.subheadline).bold().foregroundStyle(Theme.primaryText)
                    Text("@\(post.authorHandle) · \(relativeTime)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Text(post.body).font(.body).foregroundStyle(Theme.primaryText)
                HStack(spacing: 22) {
                    Label("\(post.replyCount)", systemImage: "arrowshape.turn.up.left")
                    Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
                    Label("\(post.likeCount)", systemImage: "heart")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}
