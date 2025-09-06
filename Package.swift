// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FluidVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FluidVoice", targets: ["FluidVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.13.1")
    ],
    targets: [
        .executableTarget(
            name: "FluidVoice",
            dependencies: ["Alamofire", "HotKey", "WhisperKit"],
            path: "Sources",
            exclude: ["__pycache__", "VersionInfo.swift.template"],
            resources: [
                .process("Assets.xcassets"),
                .copy("parakeet_transcribe_pcm.py"),
                .copy("parakeet_daemon.py"),
                .copy("mlx_semantic_correct.py"),
                // Bundle additional resources like uv binary and lock files
                .copy("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "FluidVoiceTests",
            dependencies: ["FluidVoice"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
