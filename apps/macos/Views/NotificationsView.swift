import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// The notifications tab: a list of likes, reposts, follows, mentions, replies and
/// quotes pulled from `app.bsky.notification.listNotifications`. Each row shows the
/// actor's avatar, what they did (icon + verb), an optional post snippet, and the
/// relative time. Mirrors the home feed's load/empty/failure states.
struct NotificationsView: View {
    @ObservedObject var model: NotificationsViewModel
    @EnvironmentObject private var theme: ThemeStore
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader { EmptyView() }
            content
        }
        .background(theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                loadingState
            case let .failed(message):
                failedState(message)
            case let .loaded(items):
                if items.isEmpty { emptyState } else { list(items) }
            }
        }
    }

    private func list(_ items: [NotificationGroup]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                NotificationRowView(item: item, now: now)
                Divider().overlay(theme.divider)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("通知を読み込んでいます…")
                .font(.callout).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26)).foregroundStyle(theme.star)
            Text("通知の読み込みに失敗しました")
                .font(.callout).foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.caption).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
            Button("再試行") { Task { await model.load() } }
                .buttonStyle(.borderedProminent).tint(theme.accent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28)).foregroundStyle(theme.tertiaryText)
            Text("通知はまだありません")
                .font(.callout).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

/// One notification row: reason icon, the actor avatar(s), a verb line, and the
/// context of what was reacted to. For likes/reposts the target post snippet is
/// shown in a quoted box (so you can see which post got the reaction); aggregated
/// reactions read "Alice 他N人 がいいねしました". For replies/mentions/quotes the
/// incoming post body is shown instead. Unread rows carry a faint accent tint.
private struct NotificationRowView: View {
    let item: NotificationGroup
    let now: Date
    @EnvironmentObject private var theme: ThemeStore

    private let timeFormatter = RelativeTimeFormatter()

    private var leadActor: NotificationGroup.Actor? { item.actors.first }
    private var othersCount: Int { max(0, item.actors.count - 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(leadActor?.displayName ?? "")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    if othersCount > 0 {
                        Text("他\(othersCount)人")
                            .font(.caption).foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }
                    Text(verb)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeFormatter.string(for: item.latestCreatedAt, now: now))
                        .font(.caption2).foregroundStyle(theme.tertiaryText)
                        .monospacedDigit()
                }
                if othersCount == 0, let handle = leadActor?.handle {
                    Text("@\(handle)")
                        .font(.caption2).foregroundStyle(theme.tertiaryText)
                        .lineLimit(1).truncationMode(.tail)
                }
                context
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(item.isRead ? Color.clear : theme.accent.opacity(0.06))
    }

    /// The post this notification is about: a quoted snippet of the target post for
    /// likes/reposts, or the incoming body for replies/mentions/quotes.
    @ViewBuilder
    private var context: some View {
        switch item.reason {
        case .like, .repost:
            if let text = item.subjectText, !text.isEmpty {
                subjectSnippet(text)
            } else if item.subjectImageURL != nil {
                subjectSnippet("")
            }
        default:
            if let text = item.text, !text.isEmpty {
                Text(text)
                    .font(.callout).foregroundStyle(theme.secondaryText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }

    private func subjectSnippet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let imageURL = item.subjectImageURL {
                RemoteImage(url: imageURL, maxPointSize: 36) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        theme.avatarPlaceholder
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if !text.isEmpty {
                Text(text)
                    .font(.caption).foregroundStyle(theme.tertiaryText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("画像")
                    .font(.caption).foregroundStyle(theme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 3)
    }

    private var avatar: some View {
        RemoteImage(url: leadActor?.avatarURL, maxPointSize: 30) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var icon: String {
        switch item.reason {
        case .like: return "heart.fill"
        case .repost: return "arrow.2.squarepath"
        case .follow: return "person.fill.badge.plus"
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .quote: return "quote.bubble.fill"
        case .other: return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch item.reason {
        case .like: return theme.star
        case .repost: return theme.accent
        default: return theme.secondaryText
        }
    }

    private var verb: String {
        switch item.reason {
        case .like: return "がいいねしました"
        case .repost: return "がリポストしました"
        case .follow: return "がフォローしました"
        case .mention: return "がメンションしました"
        case .reply: return "が返信しました"
        case .quote: return "が引用しました"
        case .other: return "のアクティビティ"
        }
    }
}
