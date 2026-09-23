// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lenotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lenotch",
            path: "Sources/Lenotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
