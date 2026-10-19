// swift-tools-version: 6.0
// Packages/GeoCore/Package.swift

import PackageDescription

let package = Package(
    name: "GeoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GeoCore", targets: ["GeoCore"]),
    ],
    targets: [
        .target(name: "GeoCore"),
        .testTarget(name: "GeoCoreTests", dependencies: ["GeoCore"]),
    ]
)
