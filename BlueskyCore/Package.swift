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
        .library(name: "YoruMimizukuKit", targets: ["YoruMimizukuKit"])
    ],
    targets: [
        .target(name: "BlueskyCore"),
        .target(name: "YoruMimizukuKit", dependencies: ["BlueskyCore"]),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"]),
        .testTarget(name: "YoruMimizukuKitTests", dependencies: ["YoruMimizukuKit"])
    ]
)
