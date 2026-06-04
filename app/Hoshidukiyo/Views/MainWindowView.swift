import SwiftUI
import HoshidukiyoKit

/// The main window: a cmux-style vertical tab rail (home, notifications, and
/// closable conversation tabs) on the left, with the selected tab's content on
/// the right. Replaces the earlier trailing inspector, which broke at narrow
/// widths. The lightbox and settings sheet float above everything.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    var accountHandle: String

    @State private var lightboxURL: URL?
    @State private var showSettings = false

    private let now = Date()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspace: workspace,
                accountHandle: accountHandle,
                onOpenSettings: { showSettings = true }
            )
            // A crisp 1px rule on the trailing edge sets the rail firmly apart from
            // the content pane, mirroring cmux's hard sidebar/content boundary.
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.divider).frame(width: 1).ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 320)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 540)
        .overlay {
            if let lightboxURL {
                ImageLightboxView(url: lightboxURL) { self.lightboxURL = nil }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(displaySettings)
        }
    }

    // MARK: - Detail routing

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            homeFeed
        case .notifications:
            notificationsPlaceholder
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    title: tab.title,
                    now: now,
                    onImageTap: { lightboxURL = $0 },
                    onOpenConversation: { workspace.openConversation($0) },
                    onClose: { workspace.closeConversation(id) }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        }
    }

    // MARK: - Home

    private var homeFeed: some View {
        VStack(spacing: 0) {
            DetailHeader {
                ChromeIconButton(
                    systemImage: "arrow.clockwise", help: "タイムラインを更新",
                    disabled: model.state.isLoading
                ) { Task { await model.load() } }
            }
            timeline
        }
        .background(theme.canvas)
        // Extend the header to the window's top edge; the hidden title bar otherwise
        // leaves a reserved safe-area band above it.
        .ignoresSafeArea(.container, edges: .top)
        .task { if case .idle = model.state { await model.load() } }
    }

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
                    post: post, density: displaySettings.density, now: now,
                    onImageTap: { lightboxURL = $0 },
                    onReplyTap: { _ in workspace.openConversation(post) }
                )
                Divider().overlay(theme.divider)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("夜空を眺めています…")
                .font(.callout)
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(theme.star)
            Text("タイムラインの読み込みに失敗しました")
                .font(.callout).foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.caption).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("再試行") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(theme.tertiaryText)
            Text("まだ投稿がありません")
                .font(.callout).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Notifications (placeholder)

    private var notificationsPlaceholder: some View {
        VStack(spacing: 0) {
            DetailHeader { EmptyView() }
            VStack(spacing: 10) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.tertiaryText)
                Text("通知はまだ準備中です")
                    .font(.callout).foregroundStyle(theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
    }
}
