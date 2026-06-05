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
                .font(.app(.callout)).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26)).foregroundStyle(theme.star)
            Text("通知の読み込みに失敗しました")
                .font(.app(.callout)).foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.app(.caption)).foregroundStyle(theme.tertiaryText)
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
                .font(.app(.callout)).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

/// One notification row, styled after the Bluesky app. A reason icon leads, followed
/// by a row of the actors' avatars (collapsed) that can expand into a per-actor list
/// with handles via a chevron. Below sits a single summary sentence ("Aliceおよび他2人が
/// あなたの投稿をいいねしました · 1分") and, for likes/reposts, the target post shown as
/// plain grey text. Replies/mentions/quotes show the incoming body. Unread rows carry
/// a faint accent tint.
private struct NotificationRowView: View {
    let item: NotificationGroup
    let now: Date
    @EnvironmentObject private var theme: ThemeStore
    @State private var isExpanded = false

    private let timeFormatter = RelativeTimeFormatter()

    private var leadName: String {
        guard let actor = item.actors.first else { return "" }
        return actor.displayName.isEmpty ? actor.handle : actor.displayName
    }

    /// Only aggregated groups (more than one actor) offer the expand/collapse toggle.
    private var canExpand: Bool { item.actors.count > 1 }

    private var displayedActors: ArraySlice<NotificationGroup.Actor> { item.actors.prefix(12) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    if isExpanded { actorList } else { avatarRow }
                    Spacer(minLength: 4)
                    if canExpand { expandToggle }
                }
                summaryLine
                context
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(item.isRead ? Color.clear : theme.accent.opacity(0.06))
    }

    /// The Bluesky-style sentence with the lead name in bold and the relative time
    /// folded in as a trailing " · 1分".
    private var summaryLine: some View {
        let summary = item.actionSummary
        let remainder = summary.hasPrefix(leadName) ? String(summary.dropFirst(leadName.count)) : summary
        let time = timeFormatter.string(for: item.latestCreatedAt, now: now)
        return (
            Text(leadName).fontWeight(.semibold).foregroundColor(theme.primaryText)
            + Text(remainder).foregroundColor(theme.primaryText)
            + Text("  ·  \(time)").foregroundColor(theme.tertiaryText)
        )
        .font(.app(.subheadline))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Collapsed state: a horizontal row of the actors' avatars.
    private var avatarRow: some View {
        HStack(spacing: 3) {
            ForEach(Array(displayedActors.enumerated()), id: \.offset) { _, actor in
                avatarCircle(actor.avatarURL, size: 26)
            }
        }
    }

    /// Expanded state: one row per actor with avatar, display name and handle.
    private var actorList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(item.actors.enumerated()), id: \.offset) { _, actor in
                HStack(spacing: 8) {
                    avatarCircle(actor.avatarURL, size: 24)
                    Text(actor.displayName.isEmpty ? actor.handle : actor.displayName)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(theme.primaryText).lineLimit(1)
                    Text("@\(actor.handle)")
                        .font(.app(.caption2)).foregroundStyle(theme.tertiaryText)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    private var expandToggle: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "非表示" : "すべて表示")
    }

    /// The post this notification is about: a plain grey snippet of the target post for
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
                    .font(.app(.callout)).foregroundStyle(theme.secondaryText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The liked/reposted post, rendered as plain grey text (no bordered box) to mirror
    /// the Bluesky app. An image-only post falls back to a small thumbnail.
    private func subjectSnippet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let imageURL = item.subjectImageURL {
                RemoteImage(url: imageURL, maxPointSize: 32) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        theme.avatarPlaceholder
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if !text.isEmpty {
                Text(text)
                    .font(.app(.subheadline)).foregroundStyle(theme.tertiaryText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("画像")
                    .font(.app(.subheadline)).foregroundStyle(theme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatarCircle(_ url: URL?, size: CGFloat) -> some View {
        RemoteImage(url: url, maxPointSize: size) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
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
}
