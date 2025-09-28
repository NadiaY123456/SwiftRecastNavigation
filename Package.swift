// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftRecastNavigation",
    platforms: [
        .visionOS(.v1),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftRecastNavigation",
            targets: ["SwiftRecastNavigation"]
        ),
    ],
    dependencies: [
        // Polyline simplification
        .package(url: "https://github.com/tomislav/Simplify-Swift.git", from: "1.0.0"),
//         SwiftEarcut: triangulation
        .package(url: "https://github.com/iShape-Swift/iTriangle", from: "1.11.0")
    ],
    targets: [
        .target(
            name: "SwiftRecastNavigation",
            dependencies: [
                "CRecast",
                .product(name: "SimplifySwift", package: "Simplify-Swift"),
                "iTriangle"
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(
            name: "CRecast"
        )
    ]
)
