import SwiftUI
import YoruMimizukuKit

/// What a post row needs to offer "リストに追加": the window's list membership
/// cache and a way to confirm the result. Absent (nil) where rows are shown
/// without a signed-in window, such as the design catalog.
struct ListMembershipContext {
    let model: ListMembershipModel
    let notify: @MainActor (String) -> Void
}

private struct ListMembershipContextKey: EnvironmentKey {
    static let defaultValue: ListMembershipContext? = nil
}

extension EnvironmentValues {
    var listMembership: ListMembershipContext? {
        get { self[ListMembershipContextKey.self] }
        set { self[ListMembershipContextKey.self] = newValue }
    }
}

/// The "リストに追加" submenu of a post row: the viewer's curated lists with a
/// check on those the author is on. A menu cannot wait for the network, so the
/// checks come from the cache (filled when the pointer or focus rests on a post);
/// until it is filled the lists are shown disabled rather than as unchecked.
/// Choosing a list re-reads the server before writing.
struct ListMembershipMenu: View {
    let context: ListMembershipContext
    @ObservedObject private var model: ListMembershipModel
    let actorDID: String
    let handle: String

    init(context: ListMembershipContext, actorDID: String, handle: String) {
        self.context = context
        self.model = context.model
        self.actorDID = actorDID
        self.handle = handle
    }

    var body: some View {
        Menu {
            if model.lists.isEmpty {
                switch model.listsState {
                case .notLoaded: Text("リストを読み込み中…")
                case .failed: Text("リストを読み込めませんでした")
                case .loaded: Text("リストがありません")
                }
            }
            let known = !model.lists.isEmpty && model.isMember(actorDID, of: model.lists[0].id) != nil
            if !model.lists.isEmpty, !known {
                Text("所属を確認中…")
            }
            ForEach(model.lists) { list in
                Toggle(list.name, isOn: Binding(
                    get: { model.isMember(actorDID, of: list.id) == true },
                    set: { member in set(member, list: list) }
                ))
                .disabled(!known)
            }
            Divider()
            Text("リストは公開され、誰でも見られます")
        } label: {
            Label("リストに追加", systemImage: "list.bullet")
        }
    }

    private func set(_ member: Bool, list: ListMembershipModel.CuratedList) {
        let notify = context.notify
        Task {
            do {
                let wrote = try await model.setMembership(actorDID, of: list.id, to: member)
                switch (member, wrote) {
                case (true, true): notify("@\(handle) を「\(list.name)」に追加しました")
                case (true, false): notify("@\(handle) はすでに「\(list.name)」にいます")
                case (false, true): notify("@\(handle) を「\(list.name)」から外しました")
                case (false, false): notify("@\(handle) は「\(list.name)」にいません")
                }
            } catch ListMembershipModel.MembershipError.listNotFound {
                notify("「\(list.name)」が見つかりませんでした")
            } catch {
                notify("リストを更新できませんでした")
            }
        }
    }
}

/// Prefetches a row author's list membership once the pointer rests on the row,
/// so the right-click menu that usually follows can show checks.
struct ListMembershipPrefetch: ViewModifier {
    let context: ListMembershipContext?
    let authorDID: String?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        if let context, let authorDID {
            content
                .onHover { isHovered = $0 }
                .task(id: isHovered) {
                    guard isHovered else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await context.model.refreshIfStale(actorDID: authorDID)
                }
        } else {
            content
        }
    }
}
