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

/// The app-menu Settings command (⌘,). Replaces the default "Settings…" item with
/// one that opens this app's in-window settings sheet, since settings live in a
/// per-window sheet rather than a separate `Settings` scene. Disabled before login,
/// when no window publishes the action.
struct SettingsCommands: Commands {
    @FocusedValue(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("設定…") { openSettings?.run() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(openSettings == nil)
        }
    }
}

/// The focused window's "open settings" action, published through `FocusedValues`
/// so the ⌘, command can reach the window that should present the sheet.
struct OpenSettingsAction {
    let run: @MainActor () -> Void
}

private struct OpenSettingsActionKey: FocusedValueKey {
    typealias Value = OpenSettingsAction
}

extension FocusedValues {
    var openSettings: OpenSettingsAction? {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }
}
