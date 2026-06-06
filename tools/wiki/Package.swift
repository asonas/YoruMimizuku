// swift-tools-version:6.0
import PackageDescription

// Tiny, dependency-free maintenance CLI for docs/wiki.
// Foundation only, so it builds and runs identically on macOS and Windows.
let package = Package(
    name: "wiki",
    targets: [
        .executableTarget(name: "wiki", path: "Sources/wiki")
    ],
    swiftLanguageModes: [.v5]
)
