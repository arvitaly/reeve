// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reeve",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ReeveKit", targets: ["ReeveKit"]),
    ],
    targets: [
        .target(
            name: "ReeveKit",
            path: "Sources/ReeveKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ReeveKitTests",
            dependencies: ["ReeveKit"],
            path: "Tests/ReeveKitTests"
        ),
    ]
)
