// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WiFiDoctor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WiFiDoctor",
            path: "Sources/WiFiDoctor"
        ),
        .testTarget(
            name: "WiFiDoctorTests",
            dependencies: ["WiFiDoctor"],
            path: "Tests/WiFiDoctorTests"
        ),
    ]
)
