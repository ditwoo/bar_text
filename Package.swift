// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bar_text",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        // Product name sets the binary name, so the .app bundle keeps
        // CFBundleExecutable = bar_text (see packaging/Info.plist).
        .executable(name: "bar_text", targets: ["BarText"])
    ],
    targets: [
        .executableTarget(
            name: "BarText",
            path: "Sources/BarText"
        ),
        .testTarget(
            name: "BarTextTests",
            dependencies: ["BarText"],
            path: "Tests/BarTextTests"
        )
    ]
)
