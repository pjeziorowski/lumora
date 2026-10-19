// swift-tools-version: 6.0
// Packages/CameraCatalog/Package.swift

import PackageDescription

let package = Package(
    name: "CameraCatalog",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CameraCatalog", targets: ["CameraCatalog"]),
    ],
    dependencies: [
        .package(path: "../OpticsCore"),
    ],
    targets: [
        .target(name: "CameraCatalog", dependencies: ["OpticsCore"], resources: [.process("Resources")]),
        .testTarget(name: "CameraCatalogTests", dependencies: ["CameraCatalog"]),
    ]
)
