// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "kastan-mcp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "kastan-mcp", targets: ["KastanMCP"]),
    ],
    dependencies: [
        .package(name: "kastan", path: ".."),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "KastanMCP",
            dependencies: [
                .product(name: "Kastan", package: "kastan"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "KastanMCPTests",
            dependencies: [
                "KastanMCP",
                .product(name: "Kastan", package: "kastan"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
