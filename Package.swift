// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Anchr",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AnchrCore", targets: ["AnchrCore"]),
        .executable(name: "AnchrApp", targets: ["AnchrApp"]),
        .executable(name: "ax-probe", targets: ["AXProbe"]),
    ],
    dependencies: [
        .package(path: "AnchrKit"),
    ],
    targets: [
        .target(
            name: "AnchrCore",
            dependencies: [
                .product(name: "AnchrKit", package: "AnchrKit"),
            ],
            path: "AnchrCore"
        ),
        .executableTarget(
            name: "AnchrApp",
            dependencies: ["AnchrCore"],
            path: "AnchrApp"
        ),
        .executableTarget(
            name: "AXProbe",
            dependencies: ["AnchrCore"],
            path: "Tools/ax-probe"
        ),
        .testTarget(
            name: "AnchrCoreTests",
            dependencies: [
                "AnchrCore",
                .product(name: "AnchrKit", package: "AnchrKit"),
                .product(name: "AnchrKitTestSupport", package: "AnchrKit"),
            ],
            path: "Tests/AnchrCoreTests"
        ),
    ]
)
