// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMarkdownView",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftMarkdownView",
            targets: ["SwiftMarkdownView"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0"),
    ],
    targets: [
        .target(
            name: "SwiftMarkdownView",
            dependencies: ["Highlightr"]
        ),
        .testTarget(
            name: "SwiftMarkdownViewTests",
            dependencies: ["SwiftMarkdownView"]
        ),
    ]
)
