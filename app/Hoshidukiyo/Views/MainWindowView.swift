import SwiftUI
import HoshidukiyoKit

/// The single-column main window: account chip, top tab bar, the live home
/// timeline, and a bottom composer placeholder.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @EnvironmentObject private var theme: ThemeStore
    var accountHandle: String

    @State private var density: DisplayDensity = .default
    @State private var selectedTab = "Home"
    @State private var showSettings = false

    private let now = Date()
    private let tabs = ["Home", "通知", "tech list", "検索"]

    var body: some View {
        VStack(spacing: 0) {
            accountChip
            tabBar
            Divider().overlay(theme.divider)
            timeline
            composer
        }
        .background(theme.background)
        .frame(minWidth: 360, minHeight: 480)
        .task { await model.load() }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(theme)
        }
    }

    private var accountChip: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape").font(.callout).foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(theme.accent).frame(width: 16, height: 16)
                Text("@\(accountHandle)").font(.caption).foregroundStyle(theme.secondaryText)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab)
                    .font(.callout)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? theme.accent : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .white : theme.secondaryText)
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
        .background(theme.surface)
    }

    private var timeline: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                ProgressView().controlSize(.small).padding(40)
            case let .failed(message):
                VStack(spacing: 8) {
                    Text("タイムラインの読み込みに失敗しました")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                    Text(message).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: 320)
                }
                .padding(40)
            case let .loaded(posts):
                if posts.isEmpty {
                    Text("まだ投稿がありません")
                        .font(.callout).foregroundStyle(theme.secondaryText).padding(40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(posts) { post in
                            PostRowView(post: post, density: density, now: now)
                            Divider().overlay(theme.divider)
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
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Post")
                .font(.callout).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(8)
        .background(theme.surface)
    }
}
