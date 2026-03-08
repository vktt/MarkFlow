// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkFlow",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MarkFlowEngine", targets: ["MarkFlowEngine"]),
        .executable(name: "MarkFlowApp", targets: ["MarkFlowApp"])
    ],
    targets: [
        .target(
            name: "MarkFlowEngine",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MarkFlowApp",
            dependencies: ["MarkFlowEngine"]
        ),
        .testTarget(
            name: "MarkFlowEngineTests",
            dependencies: ["MarkFlowEngine"]
        ),
        .testTarget(
            name: "MarkFlowAppTests",
            dependencies: ["MarkFlowApp"]
        )
    ]
)
