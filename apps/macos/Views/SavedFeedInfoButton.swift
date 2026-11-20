import SwiftUI
import YoruMimizukuKit

/// The ⓘ at the right of a pinned feed's header: who made the feed or list, what
/// it collects, and its AT-URI, so the reader can tell where the posts come from.
struct SavedFeedInfoButton: View {
    let source: SavedFeedSource
    @EnvironmentObject private var theme: ThemeStore
    @State private var isShown = false

    var body: some View {
        Button { isShown.toggle() } label: {
            Icon(.info, size: 16.25)
                .foregroundStyle(theme.tertiaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(source.kind == .feed ? "このフィードについて" : "このリストについて")
        .accessibilityLabel(source.kind == .feed ? "このフィードについて" : "このリストについて")
        .popover(isPresented: $isShown, arrowEdge: .bottom) { details }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.title)
                .font(.app(.headline))
                .foregroundStyle(theme.primaryText)
            if let description = source.description, !description.isEmpty {
                Text(description)
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let handle = source.creatorHandle {
                Text("@\(handle)")
                    .font(.app(.caption))
                    .foregroundStyle(theme.tertiaryText)
            }
            Text(source.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}
