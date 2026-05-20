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
        .target(
            name: "CTripexCore",
            dependencies: [],
            path: "Sources/CTripexCore",
            // D3D9 + Win32 + WaveOut TUs replaced by upstream_port/
            // RendererOpenGL + HostAudioSource (Chunks 3–4). main.cpp is a
            // Win32 message-loop shell with no logic to re-home — Tripex's
            // beat/fade/effect-switching state lives on the Tripex class.
            exclude: [
                "upstream/main.cpp",
                "upstream/RendererDirect3d.cpp",
                "upstream/RendererDirect3d.h",
                "upstream/AudioDevice.cpp",
                "upstream/AudioDevice.h",
                "upstream/LICENSE",
                "upstream/README.md",
                "upstream/Dll.vcxproj",
                "upstream/Tripex.vcxproj",
                "upstream/Tripex.vcxproj.filters",
                "upstream/packages.config",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream_port"),
                .define("__APPLE__"),
                .unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])
            ],
            linkerSettings: [
                // RendererOpenGL.cpp uses ImageIO + CoreGraphics to decode
                // upstream's embedded JPEG textures.
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                // OpenGL is deprecated on macOS 10.14+ but still ships;
                // link explicitly rather than relying on transitive linkage
                // from Swift's `import OpenGL.GL3`.
                .linkedFramework("OpenGL"),
            ]
        ),
        .target(
            name: "CGeissCore",
            dependencies: [],
            path: "Sources/CGeissCore",
            // Phase 4c: helper.cpp + proc_map.cpp + upstream_port/geiss_port.cpp
            // are in the compile set. The upstream main.cpp stays excluded —
            // it is a Win32/DirectDraw orchestrator, retained in tree for
            // licence + reference; the platform-neutral algorithms are pulled
            // into the build via `geiss_port.cpp` (which #includes Effects.h
            // and ports the orchestration functions). The phase-4b stub block
            // inside proc_map.cpp is no longer the global-definition site —
            // geiss_port.cpp owns them — so `GEISS_PHASE_4B_STUBS` is dropped.
            exclude: [
                "upstream/main.cpp",
                "upstream/LICENSE",
                "upstream/README.md",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream_port"),
                .define("__APPLE__"),
                .unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])
            ]
        ),
        // Lightweight core library containing model types
        // Unit tests depend only on this target for fast compilation
        .target(
            name: "NullPlayerCore",
            dependencies: [],
            path: "Sources/NullPlayerCore"
        ),
        .target(
            name: "ObjCExceptionCatcher",
            dependencies: [],
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
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
                "ObjCExceptionCatcher",
                "CVisClassicCore",
                "CGeissCore",
                "CTripexCore",
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
                .copy("Visualization/SnowShaders.metal"),
                .copy("Visualization/EKGShaders.metal"),
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
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5],
    // CTripexCore uses std::shared_ptr<T[]> (C++17). C++17 is backwards
    // compatible with CGeissCore / CVisClassicCore code.
    cxxLanguageStandard: .cxx17
)
