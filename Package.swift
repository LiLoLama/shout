// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlowLokal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // WhisperKit lebt seit 0.9.0 im Monorepo "argmax-oss-swift".
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "FlowLokal",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/FlowLokal"
        )
    ]
)
