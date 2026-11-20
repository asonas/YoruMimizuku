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
/// checks come from the cache (filled when a post is focused); choosing a list
/// re-reads the server before writing.
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
            ForEach(model.lists) { list in
                Toggle(list.name, isOn: Binding(
                    get: { model.isMember(actorDID, of: list.id) == true },
                    set: { member in set(member, list: list) }
                ))
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
            } catch {
                notify("リストを更新できませんでした")
            }
        }
    }
}
