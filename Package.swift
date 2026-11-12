// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Let the compiler find the vendored VLCKit.framework module map (Frameworks/VLCKit.framework)
// so `import VLCKit` resolves. Unsafe flags don't carry over to dependent targets, and the
// swiftbuild build system resolves NullPlayer's imports again while scanning the test target.
// Absolute, because swiftbuild runs the compiler from the package's *parent* directory: a relative
// `Frameworks` there only resolved where a stray copy happened to sit beside the checkout.
let frameworksPath = Context.packageDirectory + "/Frameworks"
let vlcKitSearchPath: SwiftSetting = .unsafeFlags(["-F", frameworksPath])

// CAvsCore build settings, shared by its C and C++ translation units. Upstream ships plain-C
// fallbacks for its inline asm (NO_MMX) but not for its SSE intrinsics, so the SSE paths
// stay on (SIMD_MODE_X86_SSE): native on x86_64, through sse2neon on arm64 via the shim
// headers in upstream_port/simd, which must be searched before the compiler's own.
let avsHeaderSearchPaths = ["upstream_port/simd", "upstream"]
let avsDefines = [
    "SIMD_MODE_X86_SSE",
    "NO_MMX",
    "_USE_MATH_DEFINES",
    "NO_FFMPEG",
    "WFMO",  // pevents' WaitForMultipleEvents, used by the platform signals
    "FORCE_CPP_FILESYSTEM_API",  // upstream's std::filesystem path for non-Linux POSIX
]
// libavs's C++ class names `FFT` and `Effect` are also defined by CVisClassicCore and
// CTripexCore; all three link into one binary, so AVS's are renamed for its TUs only.
let avsRenames = [("FFT", "AvsFFT"), ("Effect", "AvsEffect")]
// -O2 in debug too: libavs is a software renderer, and at -O0 a 524x550 frame took 55 ms
// (13 fps) against 1 ms optimised.
let avsFlags = ["-O2", "-fno-strict-aliasing", "-fwrapv", "-w"]

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
        // Video playback uses the vendored VLCKit.framework (LGPL) in Frameworks/,
        // linked via unsafeFlags on the NullPlayer target — not an SPM dependency.
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
        // Advanced Visualization Studio: libavs from grandchild/vis_avs (BSD-3) with EEL2
        // (zlib), vendored without its Win32 frontend or FFmpeg video; see skills/avs-port.
        .target(
            name: "CAvsCore",
            dependencies: [],
            path: "Sources/CAvsCore",
            exclude: [
                // EEL2's per-arch code generators are #included by nseel-cfunc.c, not compiled.
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-aarch64-gcc.c",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-aarch64-msvc.asm",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-arm-gcc.c",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-arm64ec.asm",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-ppc-gcc.c",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-x64-sse.asm",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-x86-gcc.c",
                "upstream/3rdparty/WDL-EEL2/eel2/asm-nseel-x86-msvc.c",
                // #included by nseel-yylex.c.
                "upstream/3rdparty/WDL-EEL2/eel2/y.tab.c",
                // Standalone EEL tools, not part of upstream's library build.
                "upstream/3rdparty/WDL-EEL2/eel2/eel_pp.cpp",
                "upstream/3rdparty/WDL-EEL2/eel2/loose_eel.cpp",
                "upstream/3rdparty/WDL-EEL2/eel2-add-pre-post-compile-hooks.patch",
                "upstream/3rdparty/WDL-EEL2/eel2-asm-x86-gcc-remove-gcc-vs-clang-ifdefs.patch",
                "upstream/3rdparty/WDL-EEL2/eel2-enable-eel1-compat-mode.patch",
                "upstream/3rdparty/pevents.cpp-wait-for-multiple-events-return-signal.patch",
                "upstream/3rdparty/WDL-EEL2/LICENSE.txt",
                "upstream/3rdparty/LICENSE.json.txt",
                "upstream/3rdparty/LICENSE.pevents.txt",
                "upstream/3rdparty/LICENSE.stb_image.txt",
                "upstream/LICENSE.TXT",
                "upstream_port/simd/SSE2NEON_LICENSE",
            ],
            publicHeadersPath: "include",
            cSettings: avsHeaderSearchPaths.map { .headerSearchPath($0) }
                + avsDefines.map { .define($0) }
                + avsRenames.map { .define($0.0, to: $0.1) } + [.unsafeFlags(avsFlags)],
            cxxSettings: avsHeaderSearchPaths.map { .headerSearchPath($0) }
                + avsDefines.map { .define($0) }
                + avsRenames.map { .define($0.0, to: $0.1) } + [.unsafeFlags(avsFlags)]
        ),
        // Goom (Goom2k26, LGPL-2.1): the pure-C effect core from j3k0/goom's Goom/ directory, with
        // the port's own edits (each marked in the file), behind the GoomCore.h shim; see
        // skills/goom-port.
        .target(
            name: "CGoomCore",
            dependencies: [],
            path: "Sources/CGoomCore",
            exclude: ["upstream/LICENSE", "upstream/COPYING.README"],
            publicHeadersPath: "include",
            // -O2 in debug too: a software renderer, like libavs. The two warning kinds silenced are
            // the only ones upstream raises (GNU field designators; abs() on a float in
            // tentacle3d.c, which upstream's look depends on); any other warning still shows.
            cSettings: [.headerSearchPath("upstream"),
                        .unsafeFlags(["-O2", "-Wno-gnu-designator", "-Wno-absolute-value"])]
        ),
        // Corona: libvisual's GPL-2.0-or-later port of the Sonique visualizer; skills/corona-port.
        .target(
            name: "CCoronaCore",
            dependencies: [],
            path: "Sources/CCoronaCore",
            publicHeadersPath: "include",
            // -O2 in debug too: a software renderer, like CGoomCore.
            cxxSettings: [.headerSearchPath("upstream"), .unsafeFlags(["-O2"])]
        ),
        // Smear 1.2 (BSD-style licence with a source-access clause, accepted 2026-11-12): the
        // Sonique visualizer's C renderer and Stutter script interpreter; skills/smear-port.
        .target(
            name: "CSmearCore",
            dependencies: [],
            path: "Sources/CSmearCore",
            exclude: ["upstream/LICENSE.TXT", "upstream/stutter.txt"],
            publicHeadersPath: "include",
            // -O2 in debug too: a software renderer, like CGoomCore.
            cSettings: [.headerSearchPath("upstream"), .unsafeFlags(["-O2"])]
        ),
        // Lightweight core library containing model types
        // Unit tests depend only on this target for fast compilation
        .target(
            name: "NullPlayerCore",
            dependencies: [],
            path: "Sources/NullPlayerCore"
        ),
        // The visualization cast's lock-free audio ring (C11 atomics; Swift's need macOS 15)
        .target(
            name: "CAudioTapRing",
            dependencies: [],
            path: "Sources/CAudioTapRing",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ObjCExceptionCatcher",
            dependencies: [],
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        // System library target for libprojectM (ProjectM visualization)
        // scripts/bootstrap.sh installs the headers here and the universal libprojectM-4.dylib in
        // Frameworks/, from the tarball pinned by PROJECTM_FILE. To take a new version, build it
        // universal (arm64 + x86_64), upload the tarball to the deps release, and update the pin.
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
                "CAudioTapRing",
                "CVisClassicCore",
                "CGeissCore",
                "CTripexCore",
                "CAvsCore",
                "CGoomCore",
                "CCoronaCore",
                "CSmearCore",
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "AudioStreaming",
                "CProjectM",
                "CAubio",
                "FlyingFox",
            ],
            path: "Sources/NullPlayer",
            resources: [
                .copy("Resources"),
                .copy("Visualization/SpectrumShaders.metal"),
                .copy("Visualization/SpectrogramShaders.metal"),
                .copy("Visualization/FlameShaders.metal"),
                .copy("Visualization/CosmicShaders.metal"),
                .copy("Visualization/ElectricityShaders.metal"),
                .copy("Visualization/MatrixShaders.metal"),
                .copy("Visualization/SnowShaders.metal"),
                .copy("Visualization/EKGShaders.metal"),
                .copy("ModernSkin/BloomShader.metal")
            ],
            swiftSettings: [vlcKitSearchPath],
            linkerSettings: [
                .linkedFramework("WebKit"),
                // The WMP skin engine runs skin JScript in an in-process JSContext whose only
                // reachable surface is `WMPObjectModel`; see the wmp-skin-guide skill.
                .linkedFramework("JavaScriptCore"),
                .unsafeFlags([
                    "-L", frameworksPath,
                    "-L", "/opt/homebrew/lib",
                    // Link the vendored VLCKit.framework (LGPL video engine).
                    "-F", frameworksPath,
                    "-framework", "VLCKit",
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
                "NullPlayer",
                "ZIPFoundation"
            ],
            path: "Tests/NullPlayerAppTests",
            // Committed golden PNGs for the `.wal` render sweep. They are read from the source tree
            // by path (so an update run rewrites them in place), not from a resource bundle.
            exclude: ["Fixtures", "Goldens"],
            swiftSettings: [vlcKitSearchPath],
            // The test bundle links NullPlayer's vendored libraries (VLCKit, projectM, aubio);
            // let it load them from Frameworks/ instead of from a hand-made build-dir symlink.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", Context.packageDirectory + "/Frameworks"]),
            ]
        ),
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5],
    // CTripexCore uses std::shared_ptr<T[]> (C++17). C++17 is backwards
    // compatible with CGeissCore / CVisClassicCore code.
    cxxLanguageStandard: .cxx17
)
