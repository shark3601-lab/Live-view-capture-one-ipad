// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaptureProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CaptureProbe", path: "Sources/CaptureProbe")
    ]
)
