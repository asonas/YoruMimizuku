import SwiftUI
import YoruMimizukuKit

/// The cmux-style vertical tab rail: a compact brand header, the pinned
/// home/notifications tabs, the stack of closable conversation tabs, and an
/// account footer with the settings entry point.
///
/// Visual language mirrors cmux's sidebar: dense text-first rows, a solid-fill
/// (not tinted) selection that inverts the foreground to white, rounded-6
/// corners, monospaced metadata, and a hover-revealed close affordance.
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    var accountHandle: String
    var accountAvatarURL: URL?
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            trafficLightInset
            tabList
            Spacer(minLength: 0)
            accountFooter
        }
        .background(theme.background)
        // Pull the rail up to the window's top edge; trafficLightInset below keeps the
        // first tab clear of the controls that float over this corner.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Empty top inset that keeps the first tab clear of the traffic-light controls
    /// (close/minimize/zoom) which float over the sidebar when the title bar is hidden.
    /// The sidebar carries no brand label.
    private var trafficLightInset: some View {
        Color.clear.frame(height: 28)
    }

    private var tabList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "house",
                    title: "ホーム",
                    isSelected: workspace.selection == .home
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell",
                    title: "通知",
                    isSelected: workspace.selection == .notifications
                ) { workspace.selection = .notifications }

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
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
                .font(.caption.weight(.medium))
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

    /// The signed-in account's avatar; falls back to a placeholder fill while the
    /// profile is still loading or has no avatar.
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

/// A single sidebar tab row in the cmux idiom.
///
/// - Pinned navigation rows pass an `icon` and `title` only.
/// - Conversation rows pass `title` (display name), a `subtitle` (post snippet,
///   up to two lines), and `meta` (`@handle`, monospaced), plus `onClose`.
///
/// Selection paints the whole row with a solid accent fill and switches the
/// foreground to white; hover shows a faint fill (and the close button).
private struct SidebarRow: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    var icon: String? = nil
    let title: String
    var subtitle: String? = nil
    var meta: String? = nil
    let isSelected: Bool
    var onClose: (() -> Void)? = nil
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
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius).fill(rowBackground)
            )
            .overlay(alignment: .topTrailing) { closeButton }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private var closeButton: some View {
        if let onClose, isHovered {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : theme.tertiaryText)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("タブを閉じる")
        }
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
