// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MessageIntake",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MessageIntake",
            targets: ["MessageIntake"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore"),
    ],
    targets: [
        .target(
            name: "MessageIntake",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore"),
            ],
            swiftSettings: [
                // Enable when whisper.cpp XCFramework is available
                // .define("WHISPER_CPP_AVAILABLE")
            ]
        )
    ]
)
