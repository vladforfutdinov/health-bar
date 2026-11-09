// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HealthBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HealthBarCore", targets: ["HealthBarCore"]),
    ],
    targets: [
        .target(name: "HealthBarCore", path: "Core"),
        .testTarget(
            name: "HealthBarCoreTests",
            dependencies: ["HealthBarCore"],
            path: "Tests/HealthBarCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
