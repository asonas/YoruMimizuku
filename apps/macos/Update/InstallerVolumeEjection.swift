import Foundation

/// A mounted volume described by just the facts the eject decision needs, so the
/// decision stays pure and testable while the AppKit/FileManager scanning lives
/// in `InstallerDiskImageCleaner`.
struct MountedVolume: Equatable {
    /// The volume's mount point, e.g. `/Volumes/YoruMimizuku`.
    let url: URL
    /// Whether the volume can be ejected — true for mounted disk images, false
    /// for the internal boot volume.
    let isEjectable: Bool
    /// Whether our app bundle (e.g. `YoruMimizuku.app`) sits at the volume root,
    /// which is the layout of the install DMG.
    let containsAppBundle: Bool
    /// Whether the currently running app is itself launched from this volume.
    let hostsRunningApp: Bool
}

enum InstallerVolumeEjection {
    /// Picks the mounted volumes that look like our leftover install disk image —
    /// an ejectable volume carrying our app bundle that we are not ourselves
    /// running from — so Finder stops showing the image after a manual install or
    /// a Sparkle update.
    static func volumesToEject(_ volumes: [MountedVolume]) -> [URL] {
        volumes
            .filter { $0.isEjectable && $0.containsAppBundle && !$0.hostsRunningApp }
            .map(\.url)
    }
}
