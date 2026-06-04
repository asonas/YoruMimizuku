import SwiftUI
import HoshidukiyoKit

/// The cmux-style vertical tab rail: a brand header, the pinned home/notifications
/// tabs, the stack of closable conversation tabs, and an account footer with the
/// settings entry point.
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    var accountHandle: String
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            brand
            tabList
            Spacer(minLength: 0)
            accountFooter
        }
        .background(theme.background)
    }

    private var brand: some View {
        HStack(spacing: 7) {
            Text("✦").font(.system(size: 15)).foregroundStyle(theme.star)
            Text("星月夜")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(theme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                SidebarRow(
                    icon: "house.fill", title: "ホーム",
                    isSelected: workspace.selection == .home
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell.fill", title: "通知",
                    isSelected: workspace.selection == .notifications
                ) { workspace.selection = .notifications }

                if !workspace.conversations.isEmpty {
                    sectionLabel("会話")
                    ForEach(workspace.conversations) { tab in
                        SidebarRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: tab.title,
                            isSelected: workspace.selection == .conversation(tab.id),
                            onClose: { workspace.closeConversation(tab.id) }
                        ) { workspace.selection = .conversation(tab.id) }
                    }
                }
            }
            .padding(8)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 9)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private var accountFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.accent)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
            Text("@\(accountHandle)")
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            ChromeIconButton(systemImage: "gearshape", help: "設定", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }
}

/// A single sidebar tab row. Selected rows get a leading accent bar and a tinted
/// background; closable rows reveal an X on hover.
private struct SidebarRow: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    let icon: String
    let title: String
    let isSelected: Bool
    var onClose: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? theme.accent : theme.tertiaryText)
                Text(title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let onClose, isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .help("タブを閉じる")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule().fill(theme.accent).frame(width: 3, height: 16)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected { return theme.accent.opacity(0.16) }
        return isHovered ? theme.rowHover : .clear
    }
}
