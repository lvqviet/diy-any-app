// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BatteryCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BatteryCore", targets: ["BatteryCore"]),
    ],
    targets: [
        .target(
            name: "BatteryCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"]),
    ]
)
