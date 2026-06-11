import SwiftUI

/// The File-menu command set: replaces the WindowGroup's default New Window
/// (⌘N) with 新規投稿, opening the composer in the focused window. A timeline
/// client has no use for extra timeline windows, and ⌘N matches what every
/// other Bluesky/Twitter client binds to "new post". Disabled (greyed out)
/// before login, when no window exposes the action.
struct NewPostCommands: Commands {
    @FocusedValue(\.newPost) private var newPost

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規投稿") { newPost?.run() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newPost == nil)
        }
    }
}

/// The focused window's "open the composer" action, published through
/// `FocusedValues` so the menu command above can reach the window that should
/// present the sheet.
struct NewPostAction {
    let run: @MainActor () -> Void
}

private struct NewPostActionKey: FocusedValueKey {
    typealias Value = NewPostAction
}

extension FocusedValues {
    var newPost: NewPostAction? {
        get { self[NewPostActionKey.self] }
        set { self[NewPostActionKey.self] = newValue }
    }
}
