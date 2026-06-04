// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueskyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BlueskyCore", targets: ["BlueskyCore"])
    ],
    targets: [
        .target(name: "BlueskyCore"),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"])
    ]
)
