// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kastern",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "Kastern", targets: ["Kastern"]),
        .executable(name: "kastern", targets: ["KasternCLI"]),
    ],
    targets: [
        .target(
            name: "Kastern"
        ),
        .executableTarget(
            name: "KasternCLI",
            dependencies: ["Kastern"]
        ),
        .testTarget(
            name: "KasternTests",
            dependencies: ["Kastern", "KasternCLI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
