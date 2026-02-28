// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReplyHandler",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReplyHandler",
            targets: ["ReplyHandler"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore")
    ],
    targets: [
        .target(
            name: "ReplyHandler",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore")
            ]
        )
    ]
)
