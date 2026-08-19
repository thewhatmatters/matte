// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Matte",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Matte",
            path: "Sources/Matte"
        )
    ]
)
