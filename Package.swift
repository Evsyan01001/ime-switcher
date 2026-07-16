// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ime-switcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ime-switcher",
            path: "Sources/ime-switcher"
        ),
        .executableTarget(
            name: "list-input-sources",
            path: "Tools"
        )
    ]
)
