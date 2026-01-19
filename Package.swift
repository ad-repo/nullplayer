// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AdAmp",
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
    ],
    targets: [
        .executableTarget(
            name: "AdAmp",
            dependencies: [
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "KSPlayer",
                "AudioStreaming",
            ],
            path: "Sources/AdAmp",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AdAmpTests",
            dependencies: ["AdAmp"],
            path: "Tests/AdAmpTests"
        )
    ]
)
