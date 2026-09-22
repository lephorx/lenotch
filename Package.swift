// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LephorNotch",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "LephorNotch",
            path: "Sources/LephorNotch",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
