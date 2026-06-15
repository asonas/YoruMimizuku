import AppKit
import Foundation

/// Restores reliable quit-on-Apple-event behavior for the SwiftUI life cycle.
///
/// Sparkle's "Install and Restart" terminates the app by sending a quit Apple
/// event (it deliberately never force-kills). With the SwiftUI life cycle,
/// AppKit cancels that event with `userCanceledErr` whenever any window has a
/// presented sheet — and the updater UI lives inside the settings sheet, so the
/// quit request always arrived in exactly that state: Sparkle then waited
/// silently and the update only installed on the next manual quit.
///
/// Verified empirically with a minimal WindowGroup repro: the default handler
/// cancels while a sheet is up, `applicationShouldTerminate` is never reached,
/// and even a direct `NSApp.terminate` is swallowed until the sheet is ended.
/// The working recipe is to take over the quit event handler, end every
/// attached sheet, and re-enter `terminate` on the next run-loop turn.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitEvent(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )

        // The first-time install DMG often stays mounted in Finder; eject it.
        InstallerDiskImageCleaner.ejectLeftoverInstallerVolumes()
    }

    @objc private func handleQuitEvent(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
        for window in NSApp.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
        }
        // Deferred so the sheet teardown completes first; a synchronous
        // terminate here is still swallowed by the dismissing sheet.
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
