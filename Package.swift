// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClassicAmp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ClassicAmp", targets: ["ClassicAmp"])
    ],
    dependencies: [
        // ZIP extraction for .wsz skin files
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // SQLite for media library
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0"),
        // ID3 tag parsing for metadata
        .package(url: "https://github.com/chrs1885/ID3TagEditor.git", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClassicAmp",
            dependencies: [
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "ID3TagEditor"
            ],
            path: "Sources/ClassicAmp",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ClassicAmpTests",
            dependencies: ["ClassicAmp"],
            path: "Tests/ClassicAmpTests"
        )
    ]
)
