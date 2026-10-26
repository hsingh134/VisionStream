// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisionStreamCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "VisionStreamCore", targets: ["VisionStreamCore"])],
    targets: [
        .target(name: "VisionStreamCore", path: "VisionStream/Core"),
        .testTarget(name: "VisionStreamCoreTests", dependencies: ["VisionStreamCore"], path: "Tests/CoreTests")
    ]
)
