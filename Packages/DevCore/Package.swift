// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevCore", targets: ["DevCore"]),
    ],
    targets: [
        .target(name: "DevCore"),
        .testTarget(name: "DevCoreTests", dependencies: ["DevCore"]),
    ]
)
