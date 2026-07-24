import SwiftUI

/// The File-menu command set. The spec requires multi-window support (per-window
/// account viewing, `design.md` §8), so the WindowGroup's default New Window is
/// kept, just moved off ⌘N: this client's established convention is ⌘N =
/// 新規投稿 (matching what every other Bluesky/Twitter client binds ⌘N to), so a
/// new window opens on ⇧⌘N instead, matching the Windows build's Ctrl+Shift+N.
/// 新規投稿 is disabled (greyed out) before login, when no window exposes the action.
struct NewPostCommands: Commands {
    @FocusedValue(\.newPost) private var newPost
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規投稿") { newPost?.run() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newPost == nil)
            Button("新規ウィンドウ") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
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
