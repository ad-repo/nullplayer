// swift-tools-version:6.0
//
// THROWAWAY Phase-0B feasibility harness for the Winamp Modern (.wal) effort.
// This is intentionally a SEPARATE package from the NullPlayer app so it never
// participates in the app build (respects the no-concurrent-builds rule) and can
// be deleted wholesale once Phase 0B is signed off. It reads untrusted archives
// read-only and only DUMPS inventory; it renders nothing.
import PackageDescription

let package = Package(
    name: "winamp-inventory",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "winamp-inventory",
            path: "Sources/winamp-inventory",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
