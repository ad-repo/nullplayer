// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NullPlayer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NullPlayer", targets: ["NullPlayer"])
    ],
    dependencies: [
        // ZIP extraction for .wsz skin files
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // SQLite for media library
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0"),
        // KSPlayer for MKV and extended codec support via FFmpeg
        .package(url: "https://github.com/kingslay/KSPlayer.git", branch: "main"),
        // Audio streaming with AVAudioEngine support (for Plex EQ)
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "1.4.0"),
        // Lightweight HTTP server for local file casting
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
    ],
    targets: [
        // Lightweight core library containing model types
        // Unit tests depend only on this target for fast compilation
        .target(
            name: "NullPlayerCore",
            dependencies: [],
            path: "Sources/NullPlayerCore"
        ),
        // System library target for libprojectM (ProjectM visualization)
        // To enable projectM support:
        // 1. Build libprojectM v4.1.6+ as a universal binary
        // 2. Place libprojectM-4.dylib in Frameworks/
        // 3. Uncomment the CProjectM dependency in the NullPlayer target
        .systemLibrary(
            name: "CProjectM",
            path: "Frameworks/libprojectm-4",
            pkgConfig: nil,
            providers: []
        ),
        // System library target for libaubio (BPM/tempo detection)
        .systemLibrary(
            name: "CAubio",
            path: "Frameworks/libaubio",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "NullPlayer",
            dependencies: [
                "NullPlayerCore",
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "KSPlayer",
                "AudioStreaming",
                "CProjectM",
                "CAubio",
                "FlyingFox",
            ],
            path: "Sources/NullPlayer",
            resources: [
                .copy("Resources"),
                .copy("Visualization/SpectrumShaders.metal"),
                .copy("Visualization/FlameShaders.metal"),
                .copy("Visualization/CosmicShaders.metal"),
                .copy("Visualization/ElectricityShaders.metal"),
                .copy("Visualization/MatrixShaders.metal"),
                .copy("ModernSkin/BloomShader.metal")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Frameworks",
                    "-L", "/opt/homebrew/lib",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "NullPlayerTests",
            dependencies: ["NullPlayer"],
            path: "Tests/NullPlayerTests"
        ),
        .testTarget(
            name: "NullPlayerUITests",
            dependencies: ["NullPlayer"],
            path: "Tests/NullPlayerUITests"
        )
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5]
)
