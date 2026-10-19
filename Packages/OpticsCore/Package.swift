// swift-tools-version: 6.0
// Packages/OpticsCore/Package.swift

import PackageDescription

let package = Package(
    name: "OpticsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpticsCore", targets: ["OpticsCore"]),
    ],
    targets: [
        .target(name: "OpticsCore"),
        .testTarget(name: "OpticsCoreTests", dependencies: ["OpticsCore"]),
    ]
)
