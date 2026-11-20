import SwiftUI
import YoruMimizukuKit

/// The window's right-hand column: the conversation or author page opened from
/// the timeline, with back / forward / close. Empty until something is opened.
struct DetailPaneView: View {
    @ObservedObject var pane: DetailPaneModel
    @EnvironmentObject private var theme: ThemeStore

    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onOpenAuthor: (PostDisplay) -> Void
    var onOpenQuote: (QuotedPost) -> Void
    var onReply: (PostDisplay, TimelineViewModel) -> Void
    var onQuote: (PostDisplay, TimelineViewModel) -> Void
    var onMute: (PostDisplay) -> Void
    var currentDID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let entry = pane.current {
                navigationBar
                Divider().overlay(theme.divider)
                page(for: entry)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }

    private var navigationBar: some View {
        HStack(spacing: 2) {
            barButton("chevron.left", help: "戻る", enabled: pane.canGoBack) { pane.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            barButton("chevron.right", help: "進む", enabled: pane.canGoForward) { pane.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Spacer(minLength: 0)
            barButton("xmark", help: "閉じる", enabled: true) { pane.close() }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }

    private func barButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(enabled ? theme.secondaryText : theme.tertiaryText.opacity(0.5))
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private func page(for entry: DetailEntry) -> some View {
        switch entry {
        case let .conversation(tab):
            ConversationView(
                model: tab.model,
                now: now,
                onImageTap: onImageTap,
                onOpenConversation: onOpenConversation,
                onOpenAuthor: onOpenAuthor,
                onOpenQuote: onOpenQuote
            )
            .id(tab.id)
        case let .author(tab):
            AuthorView(
                tab: tab,
                now: now,
                onImageTap: onImageTap,
                onOpenConversation: onOpenConversation,
                onOpenAuthor: onOpenAuthor,
                onReply: { onReply($0, tab.model) },
                onQuote: { onQuote($0, tab.model) },
                onOpenQuote: onOpenQuote,
                onMute: onMute,
                currentDID: currentDID
            )
            .id(tab.id)
        }
    }
}
