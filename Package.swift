// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolutionBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ResolutionBar", targets: ["ResolutionBar"])],
    targets: [
        .target(name: "ResolutionCore"),
        .executableTarget(name: "ResolutionBar", dependencies: ["ResolutionCore"]),
        .testTarget(name: "ResolutionCoreTests", dependencies: ["ResolutionCore"])
    ]
)
