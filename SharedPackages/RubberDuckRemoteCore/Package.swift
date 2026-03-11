// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RubberDuckRemoteCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RubberDuckRemoteCore",
            targets: ["RubberDuckRemoteCore"]
        )
    ],
    targets: [
        .target(
            name: "RubberDuckRemoteCore"
        ),
        .testTarget(
            name: "RubberDuckRemoteCoreTests",
            dependencies: ["RubberDuckRemoteCore"]
        )
    ]
)
