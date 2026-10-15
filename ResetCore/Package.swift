// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResetCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ResetCore", targets: ["ResetCore"])],
    targets: [
        .target(name: "ResetCore"),
        .testTarget(name: "ResetCoreTests", dependencies: ["ResetCore"]),
    ]
)
