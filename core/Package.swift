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
        .library(name: "YoruMimizukuKit", targets: ["YoruMimizukuKit"]),
        .library(name: "PlatformApple", targets: ["PlatformApple"]),
        .library(name: "PlatformWindows", targets: ["PlatformWindows"]),
        // Dynamic library so Windows produces YoruMimizukuBridge.dll, callable from
        // the WinUI 3 app via P/Invoke. macOS does not use this product.
        .library(name: "YoruMimizukuBridge", type: .dynamic, targets: ["YoruMimizukuBridge"])
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
        // Apple-only adapters: Keychain (Security), SecRandom (Security), os.signpost logger.
        // Cross-platform concretes (URLSession HTTP, swift-crypto DPoP) stay in BlueskyCore/Adapters.
        .target(name: "PlatformApple", dependencies: ["BlueskyCore"]),
        // Windows-only adapters (DPAPI secure storage, BCryptGenRandom). Sources are
        // guarded with `#if canImport(WinSDK)`, so the target compiles to an empty
        // module on non-Windows platforms.
        .target(
            name: "PlatformWindows",
            dependencies: ["BlueskyCore"],
            linkerSettings: [
                .linkedLibrary("bcrypt", .when(platforms: [.windows])),
                .linkedLibrary("crypt32", .when(platforms: [.windows]))
            ]
        ),
        // C ABI bridge for the WinUI 3 front end. Entry points are `#if os(Windows)`
        // guarded so non-Windows builds produce an empty library.
        .target(
            name: "YoruMimizukuBridge",
            dependencies: ["BlueskyCore", "YoruMimizukuKit", "PlatformWindows"]
        ),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore", "PlatformApple"]),
        .testTarget(name: "YoruMimizukuKitTests", dependencies: ["YoruMimizukuKit"]),
        .testTarget(name: "PlatformWindowsTests", dependencies: ["PlatformWindows"])
    ]
)
