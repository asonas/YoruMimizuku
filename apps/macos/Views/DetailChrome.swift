import SwiftUI

/// A named detail-pane header with optional accent glyph and contextual controls.
struct DetailHeader<Trailing: View>: View {
    @EnvironmentObject private var theme: ThemeStore
    private let title: String?
    private let icon: AppIcon?
    private let trailing: () -> Trailing

    /// Omit the title or glyph when only contextual controls are needed.
    init(_ title: String? = nil, icon: AppIcon? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Icon(icon, size: 17.5)
                    .foregroundStyle(theme.accent)
            }
            if let title {
                Text(title)
                    .font(.appSize(14, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }
}

/// A compact icon button styled to match the window chrome (rounded, recessed).
/// Used for refresh / settings / close affordances in headers and the sidebar.
struct ChromeIconButton: View {
    @EnvironmentObject private var theme: ThemeStore
    let icon: AppIcon
    var help: String = ""
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 16)
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 26)
                .background(theme.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
