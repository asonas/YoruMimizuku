import XCTest

final class InstallerVolumeEjectionTests: XCTestCase {
    private func volume(
        _ path: String,
        ejectable: Bool,
        containsApp: Bool,
        hostsRunningApp: Bool = false
    ) -> MountedVolume {
        MountedVolume(
            url: URL(fileURLWithPath: path),
            isEjectable: ejectable,
            containsAppBundle: containsApp,
            hostsRunningApp: hostsRunningApp
        )
    }

    func testNoVolumesEjectsNothing() {
        XCTAssertEqual(InstallerVolumeEjection.volumesToEject([]), [])
    }

    func testEjectsLeftoverInstallerDiskImage() {
        let volumes = [volume("/Volumes/YoruMimizuku", ejectable: true, containsApp: true)]

        XCTAssertEqual(
            InstallerVolumeEjection.volumesToEject(volumes),
            [URL(fileURLWithPath: "/Volumes/YoruMimizuku")]
        )
    }

    func testKeepsVolumeTheRunningAppLivesOn() {
        let volumes = [
            volume("/Volumes/YoruMimizuku", ejectable: true, containsApp: true, hostsRunningApp: true)
        ]

        XCTAssertEqual(InstallerVolumeEjection.volumesToEject(volumes), [])
    }

    func testKeepsEjectableVolumeWithoutTheAppBundle() {
        let volumes = [volume("/Volumes/USB", ejectable: true, containsApp: false)]

        XCTAssertEqual(InstallerVolumeEjection.volumesToEject(volumes), [])
    }

    func testKeepsNonEjectableVolumeEvenWithTheAppBundle() {
        let volumes = [volume("/", ejectable: false, containsApp: true)]

        XCTAssertEqual(InstallerVolumeEjection.volumesToEject(volumes), [])
    }
}
