// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnchrKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AnchrKit", targets: ["AnchrKit"]),
    ],
    targets: [
        .target(
            name: "AnchrKit",
            path: "Sources/AnchrKit"
        ),
        .testTarget(
            name: "AnchrKitTests",
            dependencies: ["AnchrKit"],
            path: "Tests/AnchrKitTests"
        ),
    ]
)
