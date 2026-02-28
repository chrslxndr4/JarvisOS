// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExecutionEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ExecutionEngine",
            targets: ["ExecutionEngine"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore")
    ],
    targets: [
        .target(
            name: "ExecutionEngine",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore")
            ]
        )
    ]
)
