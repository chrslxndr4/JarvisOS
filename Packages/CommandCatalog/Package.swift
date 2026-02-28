// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandCatalog",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CommandCatalog",
            targets: ["CommandCatalog"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore")
    ],
    targets: [
        .target(
            name: "CommandCatalog",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore")
            ]
        )
    ]
)
