import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// The window's right-hand column, as in the desktop prototype: a 38pt bar with
/// close, the page title and (for a conversation) the スレッド / レコード switch;
/// the page; and for a conversation a reply field at the bottom. Empty until
/// something is opened.
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
    /// Opens the reply composer for a conversation's anchor, seeded with `text`.
    var onComposeReply: (PostDisplay, String, ThreadViewModel) -> Void
    /// Sends `text` as a reply to the anchor; returns whether it was posted.
    var sendReply: (PostDisplay, String) async -> Bool
    /// Fetches a post's record as stored (`com.atproto.repo.getRecord`).
    var loadRecord: (String) async throws -> RecordResponse
    var currentDID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let entry = pane.current {
                bar(for: entry)
                Rectangle().fill(theme.divider).frame(height: 1)
                page(for: entry)
                    .frame(maxHeight: .infinity)
                if case let .conversation(conversation) = entry {
                    ReplyField(
                        model: conversation.model,
                        send: { await sendReply($0, $1) },
                        expand: { onComposeReply($0, $1, conversation.model) }
                    )
                    .id(conversation.id)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }

    private func anchorPost(_ conversation: ConversationTab) -> PostDisplay? {
        if case let .loaded(thread) = conversation.model.state { return thread.focus }
        return nil
    }

    private func bar(for entry: DetailEntry) -> some View {
        HStack(spacing: 8) {
            Button { pane.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.secondaryText)
            .help("閉じる")
            .accessibilityLabel("閉じる")

            Text(title(for: entry))
                .font(.appSize(13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .conversation = entry {
                Picker("表示", selection: $pane.tab) {
                    Text("スレッド").tag(DetailPaneModel.Tab.thread)
                    Text("レコード").tag(DetailPaneModel.Tab.record)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func title(for entry: DetailEntry) -> String {
        switch entry {
        case .conversation: return ""
        case let .author(tab): return tab.displayName.isEmpty ? "@\(tab.handle)" : tab.displayName
        }
    }

    @ViewBuilder
    private func page(for entry: DetailEntry) -> some View {
        switch entry {
        case let .conversation(conversation):
            switch pane.tab {
            case .thread:
                ConversationView(
                    model: conversation.model,
                    now: now,
                    onImageTap: onImageTap,
                    onOpenConversation: onOpenConversation,
                    onOpenAuthor: onOpenAuthor,
                    onOpenQuote: onOpenQuote,
                    onReply: { onComposeReply($0, "", conversation.model) }
                )
                .id(conversation.id)
            case .record:
                RecordView(uri: conversation.anchorID, post: anchorPost(conversation), load: loadRecord)
                    .id(conversation.id)
            }
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

/// The prototype's レコード tab: who wrote the post and where it lives, then the
/// record exactly as stored in the author's repo.
private struct RecordView: View {
    let uri: String
    let post: PostDisplay?
    let load: (String) async throws -> RecordResponse
    @EnvironmentObject private var theme: ThemeStore

    private enum State { case loading, loaded(String), failed }
    @SwiftUI.State private var state: State = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if let post {
                        row("Handle", post.authorHandle)
                    }
                    if let did = ATURI.repo(uri) {
                        row("DID", did)
                    }
                    row("URI", uri)
                    if let warning = post?.mediaWarning {
                        row("Label", warning == .graphic ? "graphic-media" : "sexual / nudity / porn")
                    }
                }
                switch state {
                case .loading:
                    ProgressView().controlSize(.small)
                case let .loaded(json):
                    Text(json)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                case .failed:
                    Text("レコードを読み込めませんでした")
                        .font(.app(.callout))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .task {
            do {
                state = .loaded(try await load(uri).prettyValue)
            } catch {
                state = .failed
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .font(.appSize(12.5))
                .foregroundStyle(theme.tertiaryText)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .textSelection(.enabled)
        }
    }
}

/// The prototype's reply field under a conversation: return sends a short
/// reply; the button opens the full composer with what was typed. Shown once
/// the thread has loaded, since the reply targets its anchor post.
private struct ReplyField: View {
    @ObservedObject var model: ThreadViewModel
    let send: (PostDisplay, String) async -> Bool
    let expand: (PostDisplay, String) -> Void
    @EnvironmentObject private var theme: ThemeStore
    @State private var text = ""
    @State private var isSending = false

    private var anchor: PostDisplay? {
        if case let .loaded(thread) = model.state { return thread.focus }
        return nil
    }

    var body: some View {
        if let anchor { field(anchor) }
    }

    private func field(_ anchor: PostDisplay) -> some View {
        HStack(spacing: 8) {
            TextField("返信", text: $text)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)
                .onSubmit { submit(anchor) }
                .accessibilityLabel("@\(anchor.authorHandle) に返信")
            Button { expand(anchor, text); text = "" } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.secondaryText)
            .help("ウインドウで書く")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.divider).frame(height: 1) }
    }

    private func submit(_ anchor: PostDisplay) {
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, !isSending else { return }
        isSending = true
        Task {
            if await send(anchor, draft) { text = "" }
            isSending = false
        }
    }
}
