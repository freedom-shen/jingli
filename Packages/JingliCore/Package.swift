// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JingliCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JingliCore", targets: ["JingliCore"])
    ],
    targets: [
        .target(name: "JingliCore"),
        .testTarget(name: "JingliCoreTests", dependencies: ["JingliCore"])
    ]
)
