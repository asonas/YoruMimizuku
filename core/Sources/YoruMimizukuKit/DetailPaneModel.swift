import Foundation

/// What the right-hand detail pane shows: one conversation or one author page.
@MainActor
public enum DetailEntry {
    case conversation(ConversationTab)
    case author(AuthorTab)
}

/// The macOS detail pane: one conversation or author page at a time, as in the
/// desktop prototype (no back/forward history). The timeline stays in its own
/// column, so opening a page here never rebuilds it.
@MainActor
public final class DetailPaneModel: ObservableObject {
    @Published public private(set) var current: DetailEntry?

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

    /// Identity of the shown page, for views that react when it changes.
    public var currentID: UUID? {
        switch current {
        case let .conversation(tab): return tab.id
        case let .author(tab): return tab.id
        case nil: return nil
        }
    }

    public func openConversation(_ post: PostDisplay) {
        if isShowingConversation(post.id) { return }
        show(.conversation(ConversationTab(anchor: post, model: makeThreadModel(post.id))))
    }

    /// Open a conversation when only the post URI and a display snippet are known
    /// (a notification subject or a quoted post).
    public func openConversation(anchorID: String, title: String, handle: String, subtitle: String) {
        if isShowingConversation(anchorID) { return }
        show(.conversation(ConversationTab(
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
        show(.author(AuthorTab(
            did: did, handle: handle, displayName: displayName, avatarURL: avatarURL,
            model: makeAuthorModel(did),
            header: makeAuthorHeader(did, initial)
        )))
    }

    /// Empty the pane.
    public func close() {
        show(nil)
    }

    private func isShowingConversation(_ anchorID: String) -> Bool {
        if case let .conversation(tab) = current { return tab.anchorID == anchorID }
        return false
    }

    /// An author feed polls only while its page is shown (the view starts it), so
    /// the page being replaced stops polling here.
    private func show(_ entry: DetailEntry?) {
        if case let .author(tab) = current { tab.model.stopPolling() }
        current = entry
    }
}
