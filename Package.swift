// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bike-tool",
    products: [
        .library(
            name: "BikeToolCore",
            targets: ["BikeToolCore"]
        ),
        .executable(
            name: "bike-tool",
            targets: ["bike-tool"]
        ),
    ],
    targets: [
        .target(
            name: "BikeToolCore"
        ),
        .executableTarget(
            name: "bike-tool",
            dependencies: ["BikeToolCore"]
        ),
        .testTarget(
            name: "bike-toolTests",
            dependencies: ["bike-tool", "BikeToolCore"],
            resources: [
                .copy("Fixtures/Chronogram Master Outline copy.bike"),
            ]
        ),
        .testTarget(
            name: "BikeToolCoreTests",
            dependencies: ["BikeToolCore"]
        ),
    ]
)
