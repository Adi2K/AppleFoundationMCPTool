// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppleFoundationMCPTool",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "AppleFoundationMCPTool",
            targets: ["AppleFoundationMCPTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.11.0"),
        .package(url: "https://github.com/mattt/AnyLanguageModel.git", from: "0.7.1"),
    ],
    targets: [
        .target(
            name: "AppleFoundationMCPTool",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]),
        .testTarget(
            name: "AppleFoundationMCPToolTests",
            dependencies: [
                "AppleFoundationMCPTool",
                .product(name: "MCP", package: "swift-sdk"),
            ]),
        .executableTarget(
            name: "AppleFoundationMCPToolExample",
            dependencies: [
                "AppleFoundationMCPTool",
            ]),
        .executableTarget(
            name: "AppleFoundationMCPToolChat",
            dependencies: [
                "AppleFoundationMCPTool",
            ]
        ),
    ]
)
