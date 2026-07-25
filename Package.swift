// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ime-switcher",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "IMECore",
            path: "Sources/IMECore"
        ),
        .executableTarget(
            name: "ime-switcher",
            dependencies: ["IMECore"],
            path: "Sources/ime-switcher"
        ),
        .executableTarget(
            name: "list-input-sources",
            path: "Tools"
        ),
        .executableTarget(
            name: "IMECoreTests",
            dependencies: ["IMECore"],
            path: "Tests/IMECoreTests"
        )
    ]
)
