import SwiftUI
import HoshidukiyoKit

/// The single-column main window: account chip, top tab bar, the live home
/// timeline, and a bottom composer placeholder.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    var accountHandle: String

    @State private var density: DisplayDensity = .default
    @State private var selectedTab = "Home"
    @State private var lightboxURL: URL?
    /// Reply-parent panes opened to the right of the timeline, forming a chain.
    @State private var detailPanes: [PostDisplay] = []

    private let now = Date()
    private let tabs = ["Home", "通知", "tech list", "検索"]

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                timelinePane
                    .frame(maxWidth: .infinity)
                ForEach(detailPanes.indices, id: \.self) { index in
                    Divider().overlay(Theme.divider)
                    PostDetailPaneView(
                        post: detailPanes[index],
                        density: density,
                        now: now,
                        onClose: { closePanes(from: index) },
                        onImageTap: { lightboxURL = $0 },
                        onReplyTap: { openParent($0, after: index) }
                    )
                    .frame(width: 360)
                }
            }
            .background(Theme.background)

            if let lightboxURL {
                ImageLightboxView(url: lightboxURL) { self.lightboxURL = nil }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task { await model.load() }
    }

    private var timelinePane: some View {
        VStack(spacing: 0) {
            accountChip
            tabBar
            Divider().overlay(Theme.divider)
            timeline
            composer
        }
    }

    /// Open `parent` in a new pane just after pane `index` (use -1 for the
    /// timeline), dropping any panes further down the chain.
    private func openParent(_ parent: PostDisplay, after index: Int) {
        var panes = Array(detailPanes.prefix(index + 1))
        panes.append(parent)
        detailPanes = panes
    }

    /// Close the pane at `index` and every pane to its right.
    private func closePanes(from index: Int) {
        detailPanes = Array(detailPanes.prefix(index))
    }

    private var accountChip: some View {
        HStack {
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                Text("@\(accountHandle)").font(.caption).foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab)
                    .font(.callout)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? Theme.accent : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .white : Theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { selectedTab = tab }
            }
            Spacer()
            Picker("表示密度", selection: $density) {
                Text("コンパクト").tag(DisplayDensity.compact)
                Text("ゆとり").tag(DisplayDensity.comfortable)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface)
    }

    private var timeline: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                ProgressView().controlSize(.small).padding(40)
            case let .failed(message):
                VStack(spacing: 8) {
                    Text("タイムラインの読み込みに失敗しました")
                        .font(.callout).foregroundStyle(Theme.secondaryText)
                    Text(message).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: 320)
                }
                .padding(40)
            case let .loaded(posts):
                if posts.isEmpty {
                    Text("まだ投稿がありません")
                        .font(.callout).foregroundStyle(Theme.secondaryText).padding(40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(posts) { post in
                            PostRowView(
                                post: post, density: density, now: now,
                                onImageTap: { lightboxURL = $0 },
                                onReplyTap: { openParent($0, after: -1) }
                            )
                            Divider().overlay(Theme.divider)
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Text("いまどうしてる?")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Post")
                .font(.callout).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(8)
        .background(Theme.surface)
    }
}
