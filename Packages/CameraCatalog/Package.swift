// swift-tools-version: 6.0
// Packages/CameraCatalog/Package.swift

import PackageDescription

let package = Package(
    name: "CameraCatalog",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CameraCatalog", targets: ["CameraCatalog"]),
    ],
    targets: [
        .target(name: "CameraCatalog"),
        .testTarget(name: "CameraCatalogTests", dependencies: ["CameraCatalog"]),
    ]
)
