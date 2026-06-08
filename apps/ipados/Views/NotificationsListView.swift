import SwiftUI
import YoruMimizukuKit

struct NotificationsListView: View {
    @ObservedObject var model: NotificationsViewModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .task { await model.load() }
            case let .failed(message):
                ContentUnavailableView("通知を読み込めませんでした", systemImage: "bell.slash", description: Text(message))
                    .toolbar {
                        Button("再試行") { Task { await model.load() } }
                    }
            case let .loaded(items):
                List(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            RemoteAvatar(url: item.actors.first?.avatarURL, size: 32)
                            Text(item.actionSummary)
                                .font(.headline)
                        }
                        if let text = item.text ?? item.subjectText {
                            Text(text)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable { await model.refresh() }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }
}
