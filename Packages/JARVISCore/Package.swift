// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JARVISCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "JARVISCore",
            targets: ["JARVISCore"]
        )
    ],
    targets: [
        .target(
            name: "JARVISCore"
        )
    ]
)
