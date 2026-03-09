// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "A10VisualLab",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "A10VisualLab", targets: ["A10VisualLab"])
    ],
    targets: [
        .executableTarget(
            name: "A10VisualLab",
            path: "Sources/A10VisualLab"
        )
    ]
)
