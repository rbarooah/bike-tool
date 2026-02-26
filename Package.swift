// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bike-tool",
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "bike-tool"
        ),
        .testTarget(
            name: "bike-toolTests",
            dependencies: ["bike-tool"],
            resources: [
                .copy("Fixtures/Chronogram Master Outline copy.bike"),
            ]
        ),
    ]
)
