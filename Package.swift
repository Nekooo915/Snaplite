// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snaplite",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Snaplite",
            path: "Sources/Snaplite"
        )
    ]
)
