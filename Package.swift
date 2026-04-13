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
        .executable(name: "NullPlayer", targets: ["NullPlayer"]),
        .executable(name: "NullPlayerCLI", targets: ["NullPlayerCLI"]),
        .executable(name: "NullPlayerLinuxUI", targets: ["NullPlayerLinuxUI"]),
    ],
    dependencies: [
        // ZIP extraction for .wsz skin files
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // SQLite for media library — pinned to 0.15.x; 0.16+ changed Expression<T> init API
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.15.4")),
        // KSPlayer for MKV and extended codec support via FFmpeg
        .package(url: "https://github.com/kingslay/KSPlayer.git", branch: "main"),
        // Audio streaming with AVAudioEngine support (for Plex EQ)
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "1.4.0"),
        // Lightweight HTTP server for local file casting
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "CVisClassicCore",
            dependencies: [],
            path: "Sources/CVisClassicCore",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath(".")
            ]
        ),
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
                "NullPlayerPlayback",
                "CVisClassicCore",
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "KSPlayer", package: "KSPlayer", condition: .when(platforms: [.macOS])),
                .product(name: "AudioStreaming", package: "AudioStreaming", condition: .when(platforms: [.macOS])),
                .target(name: "CProjectM", condition: .when(platforms: [.macOS])),
                .target(name: "CAubio", condition: .when(platforms: [.macOS])),
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
                .copy("Visualization/SnowShaders.metal"),
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
        .systemLibrary(
            name: "CGStreamer",
            path: "Sources/CGStreamer",
            pkgConfig: "gstreamer-1.0 gstreamer-audio-1.0 gstreamer-app-1.0 gstreamer-pbutils-1.0"
        ),
        .systemLibrary(
            name: "CGTK4",
            path: "Sources/CGTK4"
        ),
        .target(
            name: "NullPlayerPlayback",
            dependencies: [
                "NullPlayerCore",
                .target(name: "CGStreamer", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/NullPlayerPlayback",
            swiftSettings: [
                .define("HAVE_GSTREAMER", .when(platforms: [.linux]))
            ]
        ),
        .executableTarget(
            name: "NullPlayerCLI",
            dependencies: [
                "NullPlayerCore",
                "NullPlayerPlayback",
            ],
            path: "Sources/NullPlayerCLI"
        ),
        .executableTarget(
            name: "NullPlayerLinuxUI",
            dependencies: [
                "NullPlayerCore",
                "NullPlayerPlayback",
                .target(name: "CGTK4", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/NullPlayerLinuxUI"
        ),
        .testTarget(
            name: "NullPlayerCoreTests",
            dependencies: [
                "NullPlayerCore"
            ],
            path: "Tests/NullPlayerCoreTests"
        ),
        .testTarget(
            name: "NullPlayerAppTests",
            dependencies: [
                "NullPlayer"
            ],
            path: "Tests/NullPlayerAppTests"
        ),
        .testTarget(
            name: "NullPlayerPlaybackTests",
            dependencies: [
                "NullPlayerPlayback"
            ],
            path: "Tests/NullPlayerPlaybackTests"
        ),
        .testTarget(
            name: "NullPlayerCLITests",
            dependencies: [
                "NullPlayerCLI",
                "NullPlayerPlayback",
                "NullPlayerCore",
            ],
            path: "Tests/NullPlayerCLITests"
        ),
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx14
)
