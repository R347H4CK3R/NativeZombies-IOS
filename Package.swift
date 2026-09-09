// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SurvivalCore",
    products: [.library(name: "SurvivalCore", targets: ["SurvivalCore"])],
    targets: [
        .target(name: "SurvivalCore", path: "Sources/Core"),
        .testTarget(name: "SurvivalCoreTests", dependencies: ["SurvivalCore"], path: "Tests")
    ]
)
