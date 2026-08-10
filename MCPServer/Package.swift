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
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.101.2"),
        .package(url: "https://github.com/vapor/jwt-kit.git", exact: "5.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "KastanMCP",
            dependencies: [
                .product(name: "Kastan", package: "kastan"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "KastanMCPTests",
            dependencies: [
                "KastanMCP",
                .product(name: "Kastan", package: "kastan"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
