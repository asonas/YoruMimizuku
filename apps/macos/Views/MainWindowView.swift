import SwiftUI
import YoruMimizukuKit

/// The main window: a cmux-style vertical tab rail (home, notifications, and
/// closable conversation tabs) on the left, with the selected tab's content on
/// the right. The home feed auto-refreshes and loads older posts on scroll; j/k
/// move the focused post and Cmd-Shift-J/K cycle the tabs. The lightbox and
/// settings sheet float above everything.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @ObservedObject var notifications: NotificationsViewModel
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    @EnvironmentObject private var fontSettings: FontSettingsStore
    var accountHandle: String
    var accountAvatarURL: URL?
    /// Builds a composer VM for a new post (nil parent) or a reply (parent URI).
    var makeComposer: @MainActor (String?) -> ComposerViewModel

    @State private var lightbox: ImageGallery?
    @State private var showSettings = false
    /// The id of the post j/k navigation currently highlights.
    @State private var focusedPostID: String?
    /// The composer sheet's view model; non-nil while the sheet is open.
    @State private var composer: ComposerViewModel?

    /// How often the home feed pulls fresh posts while it is on screen.
    private let refreshInterval: Duration = .seconds(30)
    private let now = Date()

    var body: some View {
        // A stable ZStack hosts the sheet/overlays so changing the font (which
        // re-ids the inner content to refresh every `.font(.app(...))`) never
        // dismisses the settings sheet or resets `showSettings`.
        ZStack {
            splitView
                .id("\(fontSettings.family)|\(fontSettings.baseSize)")
        }
        // Cmd-Shift-J/K cycle the sidebar tabs from anywhere in the window.
        .background { tabShortcuts }
        .overlay {
            if let lightbox {
                ImageLightboxView(gallery: lightbox) { self.lightbox = nil }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(displaySettings)
                .environmentObject(fontSettings)
        }
        .sheet(item: $composer) { model in
            ComposerView(model: model) { composer = nil }
                .environmentObject(theme)
                .environmentObject(fontSettings)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(
                workspace: workspace,
                accountHandle: accountHandle,
                accountAvatarURL: accountAvatarURL,
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
    }

    // MARK: - Detail routing

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            homeFeed
        case .notifications:
            NotificationsView(model: notifications, now: now)
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) }
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
            DetailHeader { EmptyView() }
            timeline
        }
        .background(theme.canvas)
        // Extend the header to the window's top edge; the hidden title bar otherwise
        // leaves a reserved safe-area band above it.
        .ignoresSafeArea(.container, edges: .top)
        // j/k move the focused post; only meaningful on the home feed.
        .background { postNavShortcuts }
        .task { await runHomeFeed() }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
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
            .onChange(of: focusedPostID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func postList(_ posts: [PostDisplay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(posts) { post in
                PostRowView(
                    post: post, density: displaySettings.density, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onReplyTap: { _ in workspace.openConversation(post) }
                )
                .background(post.id == focusedPostID ? theme.rowHover : .clear)
                .overlay(alignment: .leading) {
                    if post.id == focusedPostID {
                        Rectangle().fill(theme.accent).frame(width: 3)
                    }
                }
                .id(post.id)
                .onAppear {
                    // Reaching the last row pulls the next older page (infinite scroll).
                    if post.id == posts.last?.id {
                        Task { await model.loadMore() }
                    }
                }
                Divider().overlay(theme.divider)
            }
            if model.isLoadingMore {
                loadMoreFooter
            }
        }
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("夜空を眺めています…")
                .font(.app(.callout))
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
                .font(.app(.callout)).foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.app(.caption)).foregroundStyle(theme.tertiaryText)
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
                .font(.app(.callout)).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Home lifecycle

    /// Load the feed once, then refresh it on an interval for as long as the home
    /// tab stays on screen. SwiftUI cancels this task on disappear, stopping the
    /// timer; returning re-runs it (the initial load is skipped once loaded).
    private func runHomeFeed() async {
        if case .idle = model.state { await model.load() }
        if focusedPostID == nil { focusedPostID = model.posts.first?.id }
        while !Task.isCancelled {
            try? await Task.sleep(for: refreshInterval)
            if Task.isCancelled { break }
            await model.refresh()
        }
    }

    /// Move the focused post by `offset` rows, clamping at the ends, and pull more
    /// posts when focus reaches the tail.
    private func focusAdjacentPost(_ offset: Int) {
        let posts = model.posts
        guard !posts.isEmpty else { return }
        if let id = focusedPostID, let index = posts.firstIndex(where: { $0.id == id }) {
            let target = max(0, min(posts.count - 1, index + offset))
            focusedPostID = posts[target].id
        } else {
            focusedPostID = posts.first?.id
        }
        if focusedPostID == posts.last?.id {
            Task { await model.loadMore() }
        }
    }

    // MARK: - Keyboard shortcuts

    /// Zero-size, invisible buttons whose key equivalents drive tab cycling. Hosted
    /// in a `.background` so they register window-wide without occupying layout.
    private var tabShortcuts: some View {
        ZStack {
            Button("") { workspace.selectNextTab() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("") { workspace.selectPreviousTab() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var postNavShortcuts: some View {
        ZStack {
            Button("") { focusAdjacentPost(1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { focusAdjacentPost(-1) }
                .keyboardShortcut("k", modifiers: [])
            Button("") {
                let vm = makeComposer(nil)
                vm.onPosted = { composer = nil; Task { await model.refresh() } }
                composer = vm
            }
            .keyboardShortcut("n", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
