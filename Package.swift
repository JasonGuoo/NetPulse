// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NetPulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NetPulse",
            path: "Sources/NetPulse",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NetPulseTests",
            dependencies: ["NetPulse"],
            path: "Tests/NetPulseTests"
        ),
    ]
)
