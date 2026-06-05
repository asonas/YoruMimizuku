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
    dependencies: [
        // swift-crypto provides an API-compatible `import Crypto` that works on
        // both Apple platforms (shimmed to CryptoKit) and Windows/Linux.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "BlueskyCore",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]
        ),
        .target(name: "YoruMimizukuKit", dependencies: ["BlueskyCore"]),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"]),
        .testTarget(name: "YoruMimizukuKitTests", dependencies: ["YoruMimizukuKit"])
    ]
)
