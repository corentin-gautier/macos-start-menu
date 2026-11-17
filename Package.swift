// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StartMenu",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "StartMenu",
            path: "Sources/StartMenu",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("OpenDirectory"),
            ]
        ),
    ]
)
