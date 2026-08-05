// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NMPBoundaryLint",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "nmp-boundary-lint", targets: ["NMPBoundaryLint"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            exact: "603.0.2"
        )
    ],
    targets: [
        .target(
            name: "NMPBoundaryCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "NMPBoundaryLint",
            dependencies: ["NMPBoundaryCore"]
        ),
        .testTarget(
            name: "NMPBoundaryCoreTests",
            dependencies: ["NMPBoundaryCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
