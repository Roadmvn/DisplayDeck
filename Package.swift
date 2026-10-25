// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DisplayDeck",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CPrivateAPI",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "DisplayDeck",
            dependencies: ["CPrivateAPI"]
        ),
    ]
)
