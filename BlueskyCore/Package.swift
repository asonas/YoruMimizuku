// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueskyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BlueskyCore", targets: ["BlueskyCore"]),
        .library(name: "HoshidukiyoKit", targets: ["HoshidukiyoKit"])
    ],
    targets: [
        .target(name: "BlueskyCore"),
        .target(name: "HoshidukiyoKit", dependencies: ["BlueskyCore"]),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"]),
        .testTarget(name: "HoshidukiyoKitTests", dependencies: ["HoshidukiyoKit"])
    ]
)
