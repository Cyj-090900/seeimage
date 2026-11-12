// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeeImage",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SeeImage", path: "Sources/SeeImage")
    ]
)
