// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HopGauge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HopGauge",
            path: "Sources/HopGauge",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HopGaugeTests",
            dependencies: ["HopGauge"],
            path: "Tests/HopGaugeTests"
        ),
    ]
)
