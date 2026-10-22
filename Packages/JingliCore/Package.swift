// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JingliCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JingliCore", targets: ["JingliCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "JingliCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "JingliCoreTests",
            dependencies: ["JingliCore"]
        )
    ]
)
