// swift-tools-version: 5.10

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
        .package(url: "https://github.com/kstenerud/KSCrash.git", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.15.7"))
    ],
    targets: [
        .executableTarget(
            name: "FluidVoice",
            dependencies: [
                "Alamofire",
                "HotKey",
                .product(name: "Installations", package: "KSCrash"),
                "FluidAudio"
            ],
            path: "Sources",
            exclude: ["VersionInfo.swift.template"],
            resources: [
                .process("Assets.xcassets")
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
            exclude: ["README.md"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
