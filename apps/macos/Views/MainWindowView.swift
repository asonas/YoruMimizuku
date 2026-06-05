import SwiftUI
import YoruMimizukuKit

/// The main window: a cmux-style vertical tab rail (home, notifications, filter,
/// and closable conversation tabs) on the left, with the selected tab's content
/// on the right. Home and filter tabs render a `FeedView`; Cmd-Shift-J/K cycle the
/// tabs. The lightbox, settings, and composer sheets float above everything.
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
    /// The composer sheet's view model; non-nil while the sheet is open.
    @State private var composer: ComposerViewModel?

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

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            FeedView(
                model: model, title: nil, now: now,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenConversation: { workspace.openConversation($0) },
                onCompose: { compose(refreshing: model) }
            )
        case .notifications:
            NotificationsView(model: notifications, now: now)
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                FeedView(
                    model: tab.model, title: tab.title, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onCompose: { compose(refreshing: tab.model) }
                )
                // Key identity on the query so editing it rebuilds the feed (and
                // restarts its load/poll task); a relabel keeps the same identity.
                .id("\(id)-\(tab.query)")
            } else {
                Color.clear.background(theme.canvas)
            }
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    title: tab.title,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onClose: { workspace.closeConversation(id) },
                    onReply: { parentURI in
                        let vm = makeComposer(parentURI)
                        vm.onPosted = { composer = nil }
                        composer = vm
                    }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        }
    }

    /// Open the composer for a new post; on success dismiss it and refresh the
    /// feed that was visible so the new post can surface.
    private func compose(refreshing model: TimelineViewModel) {
        let vm = makeComposer(nil)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

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
}
