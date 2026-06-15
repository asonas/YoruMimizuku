import AppKit
import Foundation

/// Ejects the leftover install disk image so it stops lingering in Finder.
///
/// The app ships as a DMG for first-time manual installs (the image carries the
/// `.app` next to an `/Applications` drop link). After the user drags the app
/// across, macOS leaves the image mounted, and it keeps reappearing in Finder
/// across launches and Sparkle updates. On launch we scan the mounted volumes,
/// pick the one that is our ejectable install image — but never the volume we
/// are running from — and eject it. Sparkle updates themselves ship as a ZIP and
/// mount nothing; this cleans up the image left behind by the original install.
enum InstallerDiskImageCleaner {
    static func ejectLeftoverInstallerVolumes() {
        let appBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let appBundleName = appBundleURL.lastPathComponent
        let runningAppPath = appBundleURL.path
        DispatchQueue.global(qos: .utility).async {
            let volumes = scanMountedVolumes(appBundleName: appBundleName, runningAppPath: runningAppPath)
            for url in InstallerVolumeEjection.volumesToEject(volumes) {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            }
        }
    }

    private static func scanMountedVolumes(appBundleName: String, runningAppPath: String) -> [MountedVolume] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.volumeIsEjectableKey]
        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }
        return urls.map { url in
            let isEjectable = (try? url.resourceValues(forKeys: Set(keys)))?.volumeIsEjectable ?? false
            let appBundlePath = url.appendingPathComponent(appBundleName).path
            let containsAppBundle = fileManager.fileExists(atPath: appBundlePath)
            let mountPrefix = url.path == "/" ? "/" : url.path + "/"
            let hostsRunningApp = runningAppPath.hasPrefix(mountPrefix)
            return MountedVolume(
                url: url,
                isEjectable: isEjectable,
                containsAppBundle: containsAppBundle,
                hostsRunningApp: hostsRunningApp
            )
        }
    }
}
