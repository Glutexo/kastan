// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "jizdni-nerady",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "jizdni-nerady", targets: ["jizdni-nerady"]),
    ],
    targets: [
        .executableTarget(
            name: "jizdni-nerady"
        ),
        .testTarget(
            name: "jizdni-neradyTests",
            dependencies: ["jizdni-nerady"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
