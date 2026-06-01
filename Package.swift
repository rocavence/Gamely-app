// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gamely",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(name: "CNotify", path: "Sources/CNotify"),
        .executableTarget(
            name: "Gamely",
            dependencies: ["CNotify"],
            path: "Sources/Gamely"
        ),
    ],
    swiftLanguageModes: [.v6]
)
