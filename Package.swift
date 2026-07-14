// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kastan",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "Kastan", targets: ["Kastan"]),
        .executable(name: "kastan", targets: ["KastanCLI"]),
    ],
    targets: [
        .target(
            name: "Kastan"
        ),
        .executableTarget(
            name: "KastanCLI",
            dependencies: ["Kastan"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KastanTests",
            dependencies: ["Kastan", "KastanCLI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
