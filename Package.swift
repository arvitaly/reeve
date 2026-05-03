// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reeve",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ReeveKit", targets: ["ReeveKit"]),
        .executable(name: "Reeve", targets: ["Reeve"]),
        .executable(name: "ReeveHelper", targets: ["ReeveHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "ReeveKit",
            path: "Sources/ReeveKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Reeve",
            dependencies: ["ReeveKit"],
            path: "Sources/Reeve"
        ),
        .executableTarget(
            name: "ReeveHelper",
            dependencies: ["ReeveKit"],
            path: "Sources/ReeveHelper",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ReeveKitTests",
            dependencies: ["ReeveKit"],
            path: "Tests/ReeveKitTests"
        ),
        .testTarget(
            name: "ReeveTests",
            dependencies: ["Reeve"],
            path: "Tests/ReeveTests"
        ),
        .testTarget(
            name: "ReeveSnapshotTests",
            dependencies: [
                "Reeve",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/ReeveSnapshotTests"
        ),
    ]
)
