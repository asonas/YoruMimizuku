import Foundation
import YoruMimizukuKit

/// `ConversationPersisting` backed by `UserDefaults`: the open conversation tabs
/// are stored as a single JSON blob so they survive an app restart.
struct UserDefaultsConversationStore: ConversationPersisting {
    private let key: String

    init(key: String = "workspace.conversations.v1") {
        self.key = key
    }

    func load() -> ConversationState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ConversationState.self, from: data) else {
            return ConversationState()
        }
        return state
    }

    func save(_ state: ConversationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
