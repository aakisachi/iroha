// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolderPainter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FolderPainter",
            path: "Sources/FolderPainter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
