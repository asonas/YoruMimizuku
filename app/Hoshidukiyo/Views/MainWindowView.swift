import SwiftUI
import HoshidukiyoKit

/// The main window: a refined "Nocturne" header, the live home timeline, and a
/// trailing conversation inspector for reply threads. Mock multi-tab navigation
/// and the placeholder composer were removed in favor of the one source that
/// actually works today — the home feed.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    var accountHandle: String

    @State private var density: DisplayDensity = .default
    @State private var lightboxURL: URL?
    /// The reply whose conversation is shown in the inspector; nil hides it.
    @State private var threadAnchor: PostDisplay?

    private let now = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            timeline
        }
        .background(Theme.canvas)
        .inspector(isPresented: inspectorPresented) {
            if let anchor = threadAnchor {
                ThreadInspectorView(
                    anchor: anchor,
                    now: now,
                    onClose: { threadAnchor = nil },
                    onImageTap: { lightboxURL = $0 }
                )
                .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
            }
        }
        .frame(minWidth: 520, minHeight: 600)
        .overlay {
            if let lightboxURL {
                ImageLightboxView(url: lightboxURL) { self.lightboxURL = nil }
            }
        }
        .task { await model.load() }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { threadAnchor != nil },
            set: { if !$0 { threadAnchor = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            wordmark
            sourcePill
            Spacer(minLength: 12)
            refreshButton
            densityMenu
            accountChip
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 7) {
            Text("✦")
                .font(.system(size: 16))
                .foregroundStyle(Theme.star)
            VStack(alignment: .leading, spacing: -2) {
                Text("星月夜")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.primaryText)
                Text("HOSHIDUKIYO")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .tracking(2.5)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private var sourcePill: some View {
        Label("ホーム", systemImage: "house.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.14))
            .clipShape(Capsule())
    }

    private var refreshButton: some View {
        Button {
            Task { await model.load() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 30, height: 26)
                .background(Theme.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(model.state.isLoading)
        .help("タイムラインを更新")
    }

    private var densityMenu: some View {
        Menu {
            Picker("表示密度", selection: $density) {
                Label("コンパクト", systemImage: "list.bullet").tag(DisplayDensity.compact)
                Label("ゆとり", systemImage: "rectangle.grid.1x2").tag(DisplayDensity.comfortable)
            }
        } label: {
            Image(systemName: density == .compact ? "list.bullet" : "rectangle.grid.1x2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 30, height: 26)
                .background(Theme.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("表示密度")
    }

    private var accountChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            Text("@\(accountHandle)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated.opacity(0.6))
        .clipShape(Capsule())
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                loadingState
            case let .failed(message):
                failedState(message)
            case let .loaded(posts):
                if posts.isEmpty {
                    emptyState
                } else {
                    postList(posts)
                }
            }
        }
    }

    private func postList(_ posts: [PostDisplay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(posts) { post in
                PostRowView(
                    post: post, density: density, now: now,
                    onImageTap: { lightboxURL = $0 },
                    onReplyTap: { _ in openConversation(for: post) }
                )
                Divider().overlay(Theme.divider)
            }
        }
    }

    private func openConversation(for post: PostDisplay) {
        threadAnchor = post
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("夜空を眺めています…")
                .font(.callout)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.star)
            Text("タイムラインの読み込みに失敗しました")
                .font(.callout).foregroundStyle(Theme.secondaryText)
            Text(message)
                .font(.caption).foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("再試行") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(Theme.tertiaryText)
            Text("まだ投稿がありません")
                .font(.callout).foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
