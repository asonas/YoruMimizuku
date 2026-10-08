import SwiftUI

/// A named detail-pane header with optional accent glyph and contextual controls.
struct DetailHeader<Trailing: View>: View {
    @EnvironmentObject private var theme: ThemeStore
    private let title: String?
    private let systemImage: String?
    private let trailing: () -> Trailing

    /// Omit the title or glyph when only contextual controls are needed.
    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            if let title {
                Text(title)
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.surface.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }
}

/// A compact icon button styled to match the window chrome (rounded, recessed).
/// Used for refresh / settings / close affordances in headers and the sidebar.
struct ChromeIconButton: View {
    @EnvironmentObject private var theme: ThemeStore
    let systemImage: String
    var help: String = ""
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 26)
                .background(theme.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}
