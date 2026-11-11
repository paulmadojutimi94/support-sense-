// swift-tools-version: 5.9
// The ranking engine lives in a plain SwiftPM library so it can be built and
// tested with `swift test` on macOS *or* Linux (CI), with no simulator.
// The SwiftUI app in App/ depends on this package.
import PackageDescription

let package = Package(
    name: "SupportSenseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SupportSenseCore", targets: ["SupportSenseCore"])
    ],
    targets: [
        .target(
            name: "SupportSenseCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SupportSenseCoreTests",
            dependencies: ["SupportSenseCore"]
        )
    ]
)
