// swift-tools-version: 6.0
// Packages/PlannerKit/Package.swift

import PackageDescription

let package = Package(
    name: "PlannerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlannerKit", targets: ["PlannerKit"]),
    ],
    dependencies: [
        .package(path: "../AstroCore"),
        .package(path: "../OpticsCore"),
        .package(path: "../GeoCore"),
        .package(path: "../CameraCatalog"),
    ],
    targets: [
        .target(
            name: "PlannerKit",
            dependencies: ["AstroCore", "OpticsCore", "GeoCore", "CameraCatalog"]
        ),
        .testTarget(name: "PlannerKitTests", dependencies: ["PlannerKit"]),
    ]
)
