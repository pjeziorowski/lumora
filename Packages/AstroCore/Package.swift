// swift-tools-version: 6.0
// Packages/AstroCore/Package.swift

import PackageDescription

let package = Package(
    name: "AstroCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AstroCore", targets: ["AstroCore"]),
    ],
    targets: [
        .target(name: "AstroCore"),
        .testTarget(
            name: "AstroCoreTests",
            dependencies: ["AstroCore"],
            resources: [.copy("Golden")]
        ),
    ]
)
