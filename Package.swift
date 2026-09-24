// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lenotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Lenotch",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Lenotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
