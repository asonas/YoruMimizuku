import Foundation

/// What the right-hand detail pane shows: one conversation or one author page.
@MainActor
public enum DetailEntry {
    case conversation(ConversationTab)
    case author(AuthorTab)
}

/// The macOS detail pane: one conversation or author page at a time, with a
/// back/forward history like a browser's. The timeline stays in its own column,
/// so opening a page here never rebuilds it.
@MainActor
public final class DetailPaneModel: ObservableObject {
    /// Older pages beyond this are dropped so a long reading session does not keep
    /// every visited thread and author feed in memory.
    public static let historyLimit = 30

    @Published public private(set) var history: [DetailEntry] = []
    @Published public private(set) var index: Int = -1

    private let makeThreadModel: @MainActor (String) -> ThreadViewModel
    private let makeAuthorModel: @MainActor (String) -> TimelineViewModel
    private let makeAuthorHeader: @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel

    public init(
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeAuthorModel: @escaping @MainActor (String) -> TimelineViewModel,
        makeAuthorHeader: @escaping @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel
    ) {
        self.makeThreadModel = makeThreadModel
        self.makeAuthorModel = makeAuthorModel
        self.makeAuthorHeader = makeAuthorHeader
    }

    public var current: DetailEntry? {
        history.indices.contains(index) ? history[index] : nil
    }

    /// Identity of the shown page, for views that react when it changes.
    public var currentID: UUID? {
        switch current {
        case let .conversation(tab): return tab.id
        case let .author(tab): return tab.id
        case nil: return nil
        }
    }

    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < history.count }

    public func openConversation(_ post: PostDisplay) {
        if isShowingConversation(post.id) { return }
        push(.conversation(ConversationTab(anchor: post, model: makeThreadModel(post.id))))
    }

    /// Open a conversation when only the post URI and a display snippet are known
    /// (a notification subject or a quoted post).
    public func openConversation(anchorID: String, title: String, handle: String, subtitle: String) {
        if isShowingConversation(anchorID) { return }
        push(.conversation(ConversationTab(
            anchorID: anchorID, title: title, handle: handle, subtitle: subtitle,
            model: makeThreadModel(anchorID)
        )))
    }

    /// Open a user's page. The tapped avatar's basics seed an instant header while
    /// the full profile loads.
    public func openAuthor(did: String, handle: String, displayName: String, avatarURL: URL?) {
        if case let .author(tab) = current, tab.did == did { return }
        let initial = AuthorProfile(
            did: did, handle: handle,
            displayName: displayName.isEmpty ? nil : displayName,
            avatarURL: avatarURL, bio: nil
        )
        push(.author(AuthorTab(
            did: did, handle: handle, displayName: displayName, avatarURL: avatarURL,
            model: makeAuthorModel(did),
            header: makeAuthorHeader(did, initial)
        )))
    }

    public func goBack() {
        guard canGoBack else { return }
        move { index -= 1 }
    }

    public func goForward() {
        guard canGoForward else { return }
        move { index += 1 }
    }

    /// Empty the pane and forget its history.
    public func close() {
        move {
            history.removeAll()
            index = -1
        }
    }

    private func isShowingConversation(_ anchorID: String) -> Bool {
        if case let .conversation(tab) = current { return tab.anchorID == anchorID }
        return false
    }

    /// Opening a page after going back discards the pages ahead, as a browser does.
    private func push(_ entry: DetailEntry) {
        move {
            history.removeSubrange((index + 1)...)
            history.append(entry)
            if history.count > Self.historyLimit {
                history.removeFirst(history.count - Self.historyLimit)
            }
            index = history.count - 1
        }
    }

    /// An author feed polls only while its page is shown (the view starts it), so
    /// whichever page is left behind stops polling here.
    private func move(_ change: () -> Void) {
        let leaving = current
        change()
        if case let .author(tab) = leaving {
            if case let .author(now) = current, now === tab { return }
            tab.model.stopPolling()
        }
    }
}
