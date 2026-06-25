import SwiftUI
import YoruMimizukuKit

struct NotificationsListView: View {
    @ObservedObject var model: NotificationsViewModel
    let now: Date
    var onOpenAuthor: (NotificationGroup.Actor) -> Void
    /// Open the post a notification is about (the liked/reposted target).
    var onOpenSubject: (NotificationGroup) -> Void = { _ in }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .task { await model.load() }
            case let .failed(message):
                ContentUnavailableView("通知を読み込めませんでした", systemImage: "bell.slash", description: Text(message))
                    .overlay(alignment: .bottom) {
                        Button("再試行") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
            case let .loaded(items):
                List(items) { item in
                    NotificationRowView(item: item, now: now, onOpenAuthor: onOpenAuthor, onOpenSubject: onOpenSubject)
                }
                .refreshable { await model.refresh() }
            }
        }
        .navigationTitle("Notifications")
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }
}

private struct NotificationRowView: View {
    let item: NotificationGroup
    let now: Date
    var onOpenAuthor: (NotificationGroup.Actor) -> Void
    var onOpenSubject: (NotificationGroup) -> Void

    private let timeFormatter = RelativeTimeFormatter()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Array(item.actors.prefix(5).enumerated()), id: \.offset) { _, actor in
                        Button {
                            onOpenAuthor(actor)
                        } label: {
                            RemoteAvatar(url: actor.avatarURL, size: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
                summaryLine
                context
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(item.isRead ? Color.clear : Color.blue.opacity(0.06))
    }

    /// What the notification is about: for likes/reposts, a tappable snippet of the
    /// target post (its text and/or a thumbnail) that opens that post; for
    /// replies/mentions/quotes, the incoming body text.
    @ViewBuilder
    private var context: some View {
        switch item.reason {
        case .like, .repost:
            if (item.subjectText?.isEmpty == false) || item.subjectImageURL != nil {
                Button { onOpenSubject(item) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if let imageURL = item.subjectImageURL {
                            RemoteImage(url: imageURL, maxPointSize: 36) { phase in
                                if case let .success(image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Text(item.subjectText?.isEmpty == false ? (item.subjectText ?? "") : "画像")
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.subjectURI == nil)
            }
        default:
            if let text = item.text, !text.isEmpty {
                Text(text)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var summaryLine: Text {
        Text(item.actionSummary)
            .fontWeight(.semibold)
            + Text("  ·  \(timeFormatter.string(for: item.latestCreatedAt, now: now))")
            .foregroundColor(.secondary)
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
        case .like: return .pink
        case .repost: return .blue
        default: return .secondary
        }
    }
}
