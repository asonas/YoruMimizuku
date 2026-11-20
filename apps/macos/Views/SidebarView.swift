import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// The cmux-style vertical tab rail: a compact brand header, the pinned
/// home/notifications tabs, the saved filter tabs, and an account footer with the
/// settings entry point. Conversations and authors open in the detail pane.
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var updateController: UpdateController
    /// Opens the app's native `Settings { }` scene (⌘,'s target); the gear
    /// button below calls this directly instead of toggling a per-window sheet.
    @Environment(\.openSettings) private var openSettings
    @Environment(\.listMembership) private var listMembership
    var accountHandle: String
    var accountAvatarURL: URL?
    /// The active account's DID, used to mark the current row in the switcher.
    var accountDID: String = ""
    /// All stored accounts shown in the switcher menu.
    var accounts: [AccountSummary] = []
    /// Switch the active account to the given DID.
    var onSwitchAccount: (String) -> Void = { _ in }
    /// Start the add-account login flow.
    var onAddAccount: () -> Void = {}
    /// Log out of the current account.
    var onLogout: () -> Void = {}
    /// Whether unread/new badges are shown at all (a notification setting). When
    /// false, every tab badge is suppressed regardless of its count.
    var showsBadges: Bool = true
    /// Unread counts for the pinned tabs, supplied by the owner.
    var homeUnread: Int = 0
    var notificationsUnread: Int = 0

    /// Drives the create/edit sheet. `.new` opens a blank editor; `.edit` prefills
    /// from an existing filter and preserves its id/createdAt on save.
    private enum EditorRequest: Identifiable {
        case new
        case edit(SavedFilter)

        var id: String {
            switch self {
            case .new: return "new"
            case let .edit(filter): return filter.id.uuidString
            }
        }
    }

    @State private var editorRequest: EditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            tabList
            Spacer(minLength: 0)
            accountFooter
        }
        .background {
            theme.background.ignoresSafeArea(.container, edges: .top)
        }
        .sheet(item: $editorRequest) { request in
            editor(for: request).environmentObject(theme)
        }
    }

    @ViewBuilder
    private func editor(for request: EditorRequest) -> some View {
        switch request {
        case .new:
            FilterEditorView(name: "", terms: [], combinator: .and, isEditing: false) { name, terms, combinator in
                workspace.addFilter(name: name, terms: terms, combinator: combinator)
            }
        case let .edit(filter):
            FilterEditorView(name: filter.name, terms: filter.terms, combinator: filter.combinator, isEditing: true) { name, terms, combinator in
                var edited = SavedFilter(id: filter.id, name: name, terms: terms, combinator: combinator, createdAt: filter.createdAt)
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                edited.name = trimmed.isEmpty ? edited.fallbackName : trimmed
                workspace.updateFilter(edited)
            }
        }
    }

    private var tabList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "house",
                    title: "ホーム",
                    isSelected: workspace.selection == .home,
                    badge: showsBadges ? homeUnread : 0
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell",
                    title: "通知",
                    isSelected: workspace.selection == .notifications,
                    badge: showsBadges ? notificationsUnread : 0
                ) { workspace.selection = .notifications }

                savedSection("フィード", kind: .feed, icon: "dot.radiowaves.up.forward")
                savedSection("リスト", kind: .list, icon: "list.bullet")
                filterSection
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    /// The account's pinned feeds or lists, in pin order. Hidden when none are
    /// pinned; pins are managed on the server, so there is no add button here.
    @ViewBuilder
    private func savedSection(_ label: String, kind: SavedFeedSource.Kind, icon: String) -> some View {
        let sources = workspace.savedFeeds.filter { $0.kind == kind }
        if !sources.isEmpty {
            sectionLabel(label)
            ForEach(sources) { source in
                SidebarRow(
                    icon: icon,
                    title: source.title,
                    isSelected: workspace.selection == .savedFeed(source.id)
                ) { workspace.selection = .savedFeed(source.id) }
                // Only the window account's own curated lists take people.
                .modifier(AuthorDropTarget(isEnabled: source.isCuratedList && source.creatorDID == accountDID) { author in
                    addToList(author, source)
                })
            }
        }
    }

    /// The "フィルター" section: a header with an add button, then one row per
    /// saved filter. Always shown so the user can add the first filter.
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                sectionLabel("フィルター")
                Spacer(minLength: 0)
                Button { editorRequest = .new } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("フィルターを追加")
            }

            ForEach(workspace.filters) { tab in
                FilterSidebarRow(
                    model: tab.model,
                    title: tab.title,
                    meta: tab.summary,
                    isSelected: workspace.selection == .filter(tab.id),
                    showsBadges: showsBadges,
                    onClose: { workspace.removeFilter(id: tab.id) },
                    onEdit: {
                        if let saved = workspace.savedFilter(id: tab.id) {
                            editorRequest = .edit(saved)
                        }
                    },
                    onSelect: { workspace.selection = .filter(tab.id) }
                )
                .modifier(AuthorDropTarget(isEnabled: true) { author in addToFilter(author, tab) })
            }
        }
    }

    private func addToList(_ author: DraggedAuthor, _ list: SavedFeedSource) {
        guard let listMembership else { return }
        Task {
            do {
                let wrote = try await listMembership.model.setMembership(author.did, of: list.id, to: true)
                listMembership.notify(wrote
                    ? "@\(author.handle) を「\(list.title)」に追加しました"
                    : "@\(author.handle) はすでに「\(list.title)」にいます")
            } catch {
                listMembership.notify("リストを更新できませんでした")
            }
        }
    }

    private func addToFilter(_ author: DraggedAuthor, _ tab: FilterTab) {
        let message: String
        switch workspace.addAuthor(handle: author.handle, toFilter: tab.id) {
        case .added: message = "@\(author.handle) を「\(tab.title)」に追加しました"
        case .alreadyIncluded: message = "@\(author.handle) はすでに「\(tab.title)」にいます"
        case .wouldMatchNothing: message = "「\(tab.title)」は条件を AND でつなぐため、2 人目は追加できません"
        case nil: return
        }
        listMembership?.notify(message)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appSize(10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private var accountFooter: some View {
        HStack(spacing: 8) {
            accountMenu
            Spacer(minLength: 4)
            ChromeIconButton(systemImage: "gearshape", help: "設定", action: { openSettings() })
                .overlay(alignment: .topTrailing) {
                    if updateController.updateAvailable {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    /// The account switcher: the current avatar + handle open a menu listing every
    /// stored account (a checkmark marks the active one), plus "add account" and
    /// "log out". Rendered as a borderless menu so it reads like the old footer.
    private var accountMenu: some View {
        Menu {
            Section("アカウント") {
                ForEach(accounts, id: \.did) { account in
                    Button {
                        onSwitchAccount(account.did)
                    } label: {
                        if account.did == accountDID {
                            Label(accountLabel(account), systemImage: "checkmark")
                        } else {
                            Text(accountLabel(account))
                        }
                    }
                }
            }
            Divider()
            Button {
                onAddAccount()
            } label: {
                Label("アカウントを追加…", systemImage: "person.badge.plus")
            }
            Button(role: .destructive) {
                onLogout()
            } label: {
                Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 8) {
                accountAvatar
                Text("@\(accountHandle)")
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("アカウントを切り替え")
    }

    /// The display string for one account row: its handle, or its DID when the
    /// handle is missing.
    private func accountLabel(_ account: AccountSummary) -> String {
        if let handle = account.handle, !handle.isEmpty { return "@\(handle)" }
        return account.did
    }

    private var accountAvatar: some View {
        RemoteImage(url: accountAvatarURL, maxPointSize: 20) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
    }
}

/// A single sidebar tab row in the cmux idiom. Navigation rows pass `icon`+`title`;
/// filter rows add `meta` (the query) plus `onClose`/`onEdit`; conversation rows
/// add `subtitle`+`meta`+`onClose`. Selection paints a solid accent fill and
/// switches the foreground to white; hover reveals the edit/close affordances.
private struct SidebarRow: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    var icon: String? = nil
    let title: String
    var subtitle: String? = nil
    var meta: String? = nil
    let isSelected: Bool
    var onClose: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    /// Unread/new count shown as a pill. Hidden when 0 or when the row is selected.
    var badge: Int = 0
    let action: () -> Void

    private static let cornerRadius: CGFloat = 6

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                        .foregroundStyle(iconColor)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSize(12.5, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.appSize(11))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }

                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(metaColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                if badge > 0, !isSelected {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accentForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius).fill(rowBackground)
            )
            .overlay(alignment: .topTrailing) { trailingControls }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("フィルターを編集", systemImage: "pencil")
                }
            }
            if let onClose {
                Button(role: .destructive) {
                    onClose()
                } label: {
                    Label("タブを閉じる", systemImage: "xmark")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityActions {
            if let onEdit {
                Button("フィルターを編集") { onEdit() }
            }
            if let onClose {
                Button("タブを閉じる") { onClose() }
            }
        }
    }

    /// Combines title + subtitle into one string for VoiceOver, since
    /// `.accessibilityElement(children: .combine)` merges the row's Text
    /// views but drops structure (e.g. reading order/pauses between them).
    private var accessibilityRowLabel: String {
        if let subtitle, !subtitle.isEmpty {
            return "\(title)、\(subtitle)"
        }
        return title
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isHovered, onEdit != nil || onClose != nil {
            HStack(spacing: 2) {
                if let onEdit {
                    iconButton("pencil", help: "フィルターを編集", action: onEdit)
                }
                if let onClose {
                    iconButton("xmark", help: "タブを閉じる", action: onClose)
                }
            }
            .padding(2)
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isSelected ? theme.accentForeground.opacity(0.85) : theme.tertiaryText)
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var rowBackground: Color {
        if isSelected { return theme.accent }
        return isHovered ? theme.rowHover : .clear
    }

    private var titleColor: Color { isSelected ? theme.accentForeground : theme.primaryText }
    private var subtitleColor: Color { isSelected ? theme.accentForeground.opacity(0.82) : theme.secondaryText }
    private var metaColor: Color { isSelected ? theme.accentForeground.opacity(0.7) : theme.tertiaryText }
    private var iconColor: Color { isSelected ? theme.accentForeground : theme.tertiaryText }
}

/// One filter row that observes its own `TimelineViewModel` so the unread badge
/// updates as the backing feed polls in the background.
private struct FilterSidebarRow: View {
    @ObservedObject var model: TimelineViewModel
    let title: String
    let meta: String
    let isSelected: Bool
    var showsBadges: Bool = true
    let onClose: () -> Void
    let onEdit: () -> Void
    let onSelect: () -> Void

    var body: some View {
        SidebarRow(
            icon: "line.3.horizontal.decrease",
            title: title,
            meta: meta,
            isSelected: isSelected,
            onClose: onClose,
            onEdit: onEdit,
            badge: showsBadges ? model.unreadCount : 0,
            action: onSelect
        )
    }
}

/// Accepts a post author dropped on a sidebar row and outlines the row while a
/// drag hovers over it. Disabled rows ignore the drop.
private struct AuthorDropTarget: ViewModifier {
    let isEnabled: Bool
    let onDrop: (DraggedAuthor) -> Void
    @EnvironmentObject private var theme: ThemeStore
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(theme.accent, lineWidth: 2)
                    }
                }
                .dropDestination(for: DraggedAuthor.self) { authors, _ in
                    guard let author = authors.first else { return false }
                    onDrop(author)
                    return true
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
