// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AlexanderOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AlexanderOS", targets: ["AlexanderOS"]),
    ],
    dependencies: [
        .package(path: "../Packages/JARVISCore"),
        .package(path: "../Packages/MessageIntake"),
        .package(path: "../Packages/AIRouter"),
        .package(path: "../Packages/CommandCatalog"),
        .package(path: "../Packages/ExecutionEngine"),
        .package(path: "../Packages/MemorySystem"),
        .package(path: "../Packages/ReplyHandler"),
    ],
    targets: [
        .target(
            name: "AlexanderOS",
            dependencies: [
                "JARVISCore",
                "MessageIntake",
                "AIRouter",
                "CommandCatalog",
                "ExecutionEngine",
                "MemorySystem",
                "ReplyHandler",
            ],
            path: "AlexanderOS"
        ),
    ]
)
