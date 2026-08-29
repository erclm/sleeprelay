// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SleepRelayCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SleepRelayCore", targets: ["SleepRelayCore"]),
    ],
    targets: [
        .target(name: "SleepRelayCore"),
        .testTarget(
            name: "SleepRelayCoreTests",
            dependencies: ["SleepRelayCore"]
        ),
    ]
)
