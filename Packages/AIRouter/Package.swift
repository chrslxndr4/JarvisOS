// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIRouter",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AIRouter",
            targets: ["AIRouter"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore"),
    ],
    targets: [
        .target(
            name: "AIRouter",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore"),
            ],
            swiftSettings: [
                // Enable when llama.cpp XCFramework is available
                // .define("LLAMA_CPP_AVAILABLE")
            ]
        )
    ]
)
