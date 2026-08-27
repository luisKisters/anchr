// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnchrKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AnchrKit", targets: ["AnchrKit"]),
        .library(name: "AnchrKitTestSupport", targets: ["AnchrKitTestSupport"]),
    ],
    targets: [
        .target(
            name: "AnchrKit",
            path: "Sources/AnchrKit"
        ),
        .target(
            name: "AnchrKitTestSupport",
            dependencies: ["AnchrKit"],
            path: "Sources/AnchrKitTestSupport"
        ),
        .testTarget(
            name: "AnchrKitTests",
            dependencies: ["AnchrKit", "AnchrKitTestSupport"],
            path: "Tests/AnchrKitTests",
            resources: [.copy("fixtures")]
        ),
    ]
)
