// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTPMount",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FTPMount", targets: ["FreeTP"])
    ],
    targets: [
        .executableTarget(
            name: "FreeTP",
            path: "Sources/FreeTP",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
