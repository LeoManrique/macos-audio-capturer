// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AudioCapturer",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AudioCapturer",
            path: "Sources/AudioCapturer",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
