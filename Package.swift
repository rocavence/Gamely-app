// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gamely",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Gamely",
            path: "Sources/Gamely"
        ),
    ],
    swiftLanguageModes: [.v6]
)
