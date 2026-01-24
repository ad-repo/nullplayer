// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AdAmp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AdAmp", targets: ["AdAmp"])
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
        // System library target for libprojectM (Milkdrop visualization)
        // To enable projectM support:
        // 1. Build libprojectM v4.1.6+ as a universal binary
        // 2. Place libprojectM-4.dylib in Frameworks/
        // 3. Uncomment the CProjectM dependency in the AdAmp target
        .systemLibrary(
            name: "CProjectM",
            path: "Frameworks/libprojectm-4",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "AdAmp",
            dependencies: [
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "KSPlayer",
                "AudioStreaming",
                "CProjectM",
                "FlyingFox",
            ],
            path: "Sources/AdAmp",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "Frameworks", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "AdAmpTests",
            dependencies: ["AdAmp"],
            path: "Tests/AdAmpTests"
        ),
        .testTarget(
            name: "AdAmpUITests",
            dependencies: ["AdAmp"],
            path: "Tests/AdAmpUITests"
        )
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5]
)
