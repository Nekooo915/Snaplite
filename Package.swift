// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snaplite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Snaplite", targets: ["Snaplite"]),
        .library(name: "SnapliteCore", targets: ["SnapliteCore"])
    ],
    targets: [
        .target(
            name: "SnapliteCore",
            path: "Sources/SnapliteCore"
        ),
        .executableTarget(
            name: "Snaplite",
            dependencies: ["SnapliteCore"],
            path: "Sources/Snaplite"
        ),
        .testTarget(
            name: "SnapliteTests",
            dependencies: ["SnapliteCore"],
            path: "Tests/SnapliteTests"
        )
    ]
)
