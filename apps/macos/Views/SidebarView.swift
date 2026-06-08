import SwiftUI
import YoruMimizukuKit

/// The cmux-style vertical tab rail: a compact brand header, the pinned
/// home/notifications tabs, the saved filter tabs, the stack of closable
/// conversation tabs, and an account footer with the settings entry point.
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    var accountHandle: String
    var accountAvatarURL: URL?
    var onOpenSettings: () -> Void
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
            trafficLightInset
            tabList
            Spacer(minLength: 0)
            accountFooter
        }
        .background(theme.background)
        .ignoresSafeArea(.container, edges: .top)
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

    private var trafficLightInset: some View {
        Color.clear.frame(height: 28)
    }

    private var tabList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "house",
                    title: "ホーム",
                    isSelected: workspace.selection == .home,
                    badge: homeUnread
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell",
                    title: "通知",
                    isSelected: workspace.selection == .notifications,
                    badge: notificationsUnread
                ) { workspace.selection = .notifications }

                filterSection

                if !workspace.conversations.isEmpty {
                    sectionLabel("会話")
                    ForEach(workspace.conversations) { tab in
                        SidebarRow(
                            title: tab.title,
                            subtitle: tab.subtitle,
                            meta: tab.handle,
                            isSelected: workspace.selection == .conversation(tab.id),
                            onClose: { workspace.closeConversation(tab.id) }
                        ) { workspace.selection = .conversation(tab.id) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
                    onClose: { workspace.removeFilter(id: tab.id) },
                    onEdit: {
                        if let saved = workspace.savedFilter(id: tab.id) {
                            editorRequest = .edit(saved)
                        }
                    },
                    onSelect: { workspace.selection = .filter(tab.id) }
                )
            }
        }
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
            accountAvatar
            Text("@\(accountHandle)")
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            ChromeIconButton(systemImage: "gearshape", help: "設定", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
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
                        .foregroundStyle(.white)
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
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : theme.tertiaryText)
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: Color {
        if isSelected { return theme.accent }
        return isHovered ? theme.rowHover : .clear
    }

    private var titleColor: Color { isSelected ? .white : theme.primaryText }
    private var subtitleColor: Color { isSelected ? Color.white.opacity(0.82) : theme.secondaryText }
    private var metaColor: Color { isSelected ? Color.white.opacity(0.7) : theme.tertiaryText }
    private var iconColor: Color { isSelected ? .white : theme.tertiaryText }
}

/// One filter row that observes its own `TimelineViewModel` so the unread badge
/// updates as the backing feed polls in the background.
private struct FilterSidebarRow: View {
    @ObservedObject var model: TimelineViewModel
    let title: String
    let meta: String
    let isSelected: Bool
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
            badge: model.unreadCount,
            action: onSelect
        )
    }
}
