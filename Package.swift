// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HingeGuard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HingeGuard",
            path: "Sources/HingeGuard"
        )
    ]
)
