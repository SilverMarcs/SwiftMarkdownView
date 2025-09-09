// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftMarkdownView",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftMarkdownView",
            targets: ["SwiftMarkdownView"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftMarkdownView",
            resources: [
              .process("Resources")
            ]
        ),
    ]
)
