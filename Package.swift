// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Zonic",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Zonic",
            path: "Sources/Zonic"
        )
    ]
)
