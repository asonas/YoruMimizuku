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

// The app-menu Settings command (⌘,) is no longer a custom `CommandGroup`: now
// that the app declares a native `Settings { }` scene (`YoruMimizukuApp.swift`),
// SwiftUI wires ⌘, to open it automatically. The former `SettingsCommands` /
// `OpenSettingsAction` / `FocusedValues.openSettings` plumbing that routed ⌘,
// to a per-window settings sheet is removed along with the sheet itself
// (`2026-07-24-apple-hig-remediation.md` S7).
