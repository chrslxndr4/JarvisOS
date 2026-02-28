// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemorySystem",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MemorySystem",
            targets: ["MemorySystem"]
        )
    ],
    dependencies: [
        .package(path: "../JARVISCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "MemorySystem",
            dependencies: [
                .product(name: "JARVISCore", package: "JARVISCore"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
