// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlowLokal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // WhisperKit lebt seit 0.9.0 im Monorepo "argmax-oss-swift".
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        // In-process LLM (Formatting-Layer) via MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        // Tokenizer + Hub-Client, die mlx-swift-lm bewusst NICHT selbst mitbringt.
        // swift-transformers auf WhisperKits Range gepinnt (0.16 verlangt 1.1.6..<1.2.0),
        // damit beide Stacks im selben Binary koexistieren. AutoTokenizer ist hier vorhanden;
        // HubClient kommt aus dem eigenständigen swift-huggingface.
        .package(url: "https://github.com/huggingface/swift-transformers", "1.1.6" ..< "1.2.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "FlowLokal",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface")
            ],
            path: "Sources/FlowLokal"
        )
    ]
)
